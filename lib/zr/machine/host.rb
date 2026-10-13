# frozen_string_literal: true

require "fiddle"
# The frames of the running fiber, for the collector's roots
# (`Host#live_roots`). The host is a tool of the tests and of zr-dev; a
# build never loads it.
require "debug_inspector"
require_relative "../prism"
require_relative "description"
require_relative "lower"
require_relative "host/memory"

module Zr
  module Machine
    # The kernel on CRuby. The kernel's files are plain Ruby in
    # `module Zr::Kern`, and a host loads them into this ruby: each
    # `def` is a method of the module, and the forms that a build lowers
    # (`Machine.*`, `Libc.*`, layouts, signatures) are objects here that act on
    # the process's real memory through Fiddle.
    #
    # The values follow the kernel's type model (docs/reference/kernel-subset.md): an I8, I32, Word or Value is an
    # Integer in the signed range of its width, a Ptr an Integer in
    # [0, 2**64), a Bool true or false, and an F64 a Float. The lowering
    # refuses each form whose meaning on this model differs from the
    # native one, so a def runs here as it runs in a binary.
    #
    # Only one kernel is `Zr::Kern` at a time; a new Host replaces it. A
    # build never loads this file.
    class Host
      # @rbs @externs: Hash[String, Integer]
      # @rbs @statics: Hash[String, Integer]
      # @rbs @bytes: Hash[String, Integer]
      # @rbs @callables: Hash[Integer, Proc]
      # @rbs @def_names: Hash[Integer, String]
      # @rbs @closures: Hash[String, Fiddle::Closure::BlockCaller]
      # @rbs @functions: Hash[[Integer, Array[Type], Type], Fiddle::Function]
      # @rbs @errno: Integer
      # @rbs @stack_key: Symbol
      # @rbs @stacks: Array[Stack]
      # @rbs @rooted: Hash[String, Array[Symbol]]
      # @rbs @collecting: bool
      # @rbs @errno_location: Integer?
      # @rbs @barriers: bool
      # @rbs @unit: Lower

      WORD = 1 << 64
      MASK = WORD - 1
      SIGN = 1 << 63

      # A type of the kernel: its name, its size in memory, its type for
      # Fiddle, its `pack` format (`packing`), and its IO::Buffer types for
      # a load (`loads`) and a store (`stores`). A store takes a value of the signed or the unsigned range
      # alike: `pack` and an unsigned IO::Buffer type take either.
      #
      # The fields of Host's records are typed in sig/zr/machine/host.rbs,
      # the methods here.
      # @rbs skip
      Type = Data.define(:name, :size, :fiddle, :packing, :loads, :stores)

      class Type
        #: () -> String
        def inspect = name
      end
      TYPES = [
        Type.new("Word", 8, Fiddle::TYPE_LONG_LONG, "q<", :s64, :u64), Type.new("Value", 8, Fiddle::TYPE_LONG_LONG, "q<", :s64, :u64),
        Type.new("Ptr", 8, Fiddle::TYPE_VOIDP, "Q<", :u64, :u64), Type.new("I32", 4, Fiddle::TYPE_INT, "l<", :s32, :u32),
        Type.new("I8", 1, Fiddle::TYPE_CHAR, "c", :S8, :U8), Type.new("Bool", 1, Fiddle::TYPE_CHAR, "C", :U8, :U8),
        Type.new("F64", 8, Fiddle::TYPE_DOUBLE, "E", :f64, :f64), Type.new("Void", 0, Fiddle::TYPE_VOID, nil, nil, nil)
      ].to_h { |type| [type.name, type] }.freeze #: Hash[String, Type]

      # The Type of a kernel type name. A view of a layout (`IvTab`) is a
      # Ptr.
      #: (String name) -> Type
      def self.type(name) = TYPES.fetch(name) { TYPES.fetch("Ptr") }

      # The bits of `n` as a signed 64-bit Integer. Most words are in the
      # range already, and the test for that makes no Bignum.
      #: (Integer n) -> Integer
      def self.signed(n)
        return n if n.bit_length < 64

        n &= MASK
        n < SIGN ? n : n - WORD
      end

      # The bits of `n` as an unsigned 64-bit Integer.
      #: (Integer n) -> Integer
      def self.unsigned(n) = !n.negative? && n.bit_length <= 64 ? n : n & MASK

      # An Integer, a Bool as 1 or 0, or the address of a view.
      #: (Integer | bool | View | nil value) -> Integer
      def self.bits(value)
        # @type var value: untyped
        case value
        when true then 1
        when false, nil then 0
        when View then value.at
        else value
        end
      end

      # The memory of a layout at an address: `RArray[p]`. Each kernel
      # `class Name < Layout` is a subclass of the host's `Layout`
      # (`view_base`), and each `attr_accessor` or `attr_reader` of its
      # body reads, and writes, one field (`Host#view_fields`). A field of
      # a layout type reads as a view of that layout. In a binary a view
      # is only its address.
      class View
        attr_reader :at #: Integer

        #: (Integer at) -> void
        def initialize(at)
          @at = at
        end

        # The view of this layout at `address`. A view does not change, so
        # the last one that a layout made serves again for the same
        # address: the kernel reads several fields of one object in a row,
        # and a view for each read was most of what the host allocated.
        #: (Integer | bool | View | nil address) -> instance
        def self.[](address)
          # @type ivar @last: View?
          at = address.is_a?(Integer) ? address : Host.bits(address)
          last = @last
          return last if last && last.at == at

          @last = new(at)
        end

        # Defines the reader `name`, which answers what `read` gives for
        # the view's address.
        #: (Symbol name, ^(Integer at) -> untyped read) -> void
        def self.reader(name, read)
          define_method(name) do
            # @type self: View
            read.call(@at)
          end
        end
      end

      # `Libc`: a kernel file opens it and declares a C function as
      # `def self.name(...) = Machine.import`, and `Libc.name(...)` calls
      # it. A def of the same name answers the import, as the lowering's
      # `answers_import` says.
      #
      # The first call of an import finds what answers it (`Host#answer`),
      # and the import's method becomes that: later calls go straight to
      # it. The kernel's own defs are all loaded by then, and the host's
      # layers prepended.
      class Libc < Module
        # @rbs @host: Host

        #: (Host host) -> void
        def initialize(host)
          super()
          @host = host
          @imports = {}
        end

        # Gives each import that the kernel files declare its answer on
        # first call. (It is not named `bind`: that is a libc call.)
        #: (Hash[String, Import | Raw] imports) -> void
        def bind_imports(imports)
          imports.each_value do |import|
            next unless import.is_a?(Import)

            params = import.params.map { |type| Host.type(type) }
            ret = Host.type(import.ret)
            name = import.name.to_sym
            @imports[import.name] = [params, ret]
            define_singleton_method(name) { |*args| answer(name, params, ret).call(*args) }
          end
        end

        attr_reader :imports #: Hash[String, [Array[Type], Type]]

        private

        #: (Symbol name, Array[Type] params, Type ret) -> Proc
        def answer(name, params, ret)
          body = @host.answer(name.to_s, params, ret)
          define_singleton_method(name, body)
          body
        end
      end

      # The intrinsics, `Machine.*`, as the lowering defines them
      # (`Function#intrinsic`). A name's id, static and address do not
      # change, so each is found once.
      class Intrinsics
        # @rbs @host: Host
        # @rbs @ids: Hash[Symbol, Integer]
        # @rbs @statics: Hash[Symbol, Integer]
        # @rbs @addrs: Hash[Symbol, Integer]
        # @rbs @bytes: Hash[String, Integer]

        #: (Host host) -> void
        def initialize(host)
          @host = host
          @ids = {}
          @statics = {}
          @addrs = {}
          bytes = {} #: Hash[String, Integer]
          @bytes = bytes.compare_by_identity
        end

        #: (Symbol name) -> Integer
        def id(name) = @ids[name] ||= @host.symbols.id(name.to_s)

        # The bodies of the declarations `def self.name(...) =
        # Machine.import`, `def self.call(fn, ...) = Machine.indirect` and
        # `def name(...) = Machine.raw`. The host binds each declaration
        # when it loads the kernel, so a body that runs is a host bug.
        #: (?from: String?) -> bot
        def import(from: nil) = raise(NotImplementedError, "an import that the host did not bind#{" (#{from})" if from}")
        #: () -> bot
        def indirect = raise(NotImplementedError, "a signature that the host did not bind")
        #: () -> bot
        def raw = raise(NotImplementedError, "a raw function that the host does not have")
        #: (String string) -> Integer
        def bytesize(string) = string.bytesize
        #: (String string) -> Integer
        def bytes(string) = @bytes[string] ||= @host.bytes(string)
        #: (Symbol name) -> Integer
        def extern(name) = @host.extern(name.to_s)
        #: (Symbol name, Integer size) -> Integer
        def static(name, size) = @statics[name] ||= @host.static(name.to_s, size)
        # An exported area of a C name (`Machine.global`): a static here,
        # in a namespace of its own.
        #: (Symbol name, ?Integer size) -> Integer
        def global(name, size = 8) = static(:"global #{name}", size)
        #: (Integer size) -> Integer
        def slot(size) = @host.slot(size)
        #: (Symbol name) -> Integer
        def addr(name) = @addrs[name] ||= @host.addr(name.to_s)

        LOAD64 = Memory.reader(TYPES["Word"], 0) #: ^(Integer) -> untyped
        LOAD32 = Memory.reader(TYPES["I32"], 0) #: ^(Integer) -> untyped
        LOAD8 = Memory.reader(TYPES["I8"], 0) #: ^(Integer) -> untyped
        STORE64 = Memory.writer(TYPES["Word"], 0) #: ^(Integer, untyped) -> untyped
        STORE32 = Memory.writer(TYPES["I32"], 0) #: ^(Integer, untyped) -> untyped
        STORE8 = Memory.writer(TYPES["I8"], 0) #: ^(Integer, untyped) -> untyped

        #: (Integer p, Integer off) -> Integer
        def load64(p, off) = LOAD64.call(p + off)
        #: (Integer p, Integer off) -> Integer
        def load32(p, off) = LOAD32.call(p + off)
        #: (Integer p, Integer off) -> Integer
        def load8(p, off) = LOAD8.call(p + off)
        #: (Integer p, Integer off, Integer value) -> untyped
        def store64(p, off, value) = STORE64.call(p + off, value)
        #: (Integer p, Integer off, Integer value) -> untyped
        def store32(p, off, value) = STORE32.call(p + off, value)
        #: (Integer p, Integer off, Integer value) -> untyped
        def store8(p, off, value) = STORE8.call(p + off, value)

        # The gate word is in a register, and in the static `gates`, which
        # `gates_enter` reads (`Function#gates_addr`). Here the host keeps
        # the register's copy (`Host#gates`), which the walker reads.
        #: () -> Integer
        def gates = @host.gates

        #: (Integer word) -> void
        def gates_set(word)
          @host.gates = word
          STORE64.call(static(:gates, 8), word)
        end

        # The walker has no machine stack for a C caller's arguments: a
        # variadic C-API function runs only in a binary.
        #: (Integer _kind) -> Integer
        def va_list(_kind) = raise(NotImplementedError, "a variadic C-API function runs only in a binary")

        #: () -> void
        def gates_enter
          @host.gates = LOAD64.call(static(:gates, 8))
        end

        # A Word of `x`: an Integer in the signed range is one already.
        #: (Integer | bool | View | nil x) -> Integer
        def word(x) = x.is_a?(Integer) && x.bit_length < 64 ? x : Host.signed(Host.bits(x))
        #: (Integer | bool | View | nil x) -> Integer
        def sword(x) = word(x)
        #: (Integer | bool | View | nil x) -> Integer
        def value(x) = @host.pin(word(x))
        #: (Integer | bool | View | nil x) -> Integer
        def ptr(x) = Host.unsigned(Host.bits(x))
        #: (Integer x) -> Integer
        def u8(x) = x & 0xFF
        #: (Integer x) -> Integer
        def u32(x) = x & 0xFFFF_FFFF
        #: (Integer | bool | nil x) -> Integer
        def i8(x) = narrow(Host.bits(x), 8)
        #: (Integer | bool | nil x) -> Integer
        def i32(x) = narrow(Host.bits(x), 32)

        #: (Integer a, Integer b) -> Integer
        def add_wrap(a, b) = Host.signed(a + b)
        #: (Integer a, Integer b) -> Integer
        def sub_wrap(a, b) = Host.signed(a - b)
        #: (Integer a, Integer b) -> Integer
        def mul_wrap(a, b) = Host.signed(a * b)
        #: (Integer a, Integer b) -> Integer
        def shl_wrap(a, b) = Host.signed(a << (b & 63))
        #: (Integer a, Integer b) -> Integer
        def uadd_wrap(a, b) = Host.unsigned(a + b)
        #: (Integer a, Integer b) -> Integer
        def usub_wrap(a, b) = Host.unsigned(a - b)
        #: (Integer a, Integer b) -> Integer
        def umul_wrap(a, b) = Host.unsigned(a * b)
        #: (Integer a, Integer b) -> Integer
        def ushl_wrap(a, b) = Host.unsigned(a << (b & 63))

        # Division that truncates toward zero, as C's.
        #: (Integer a, Integer b) -> Integer
        def sdiv(a, b)
          q = a.abs / b.abs
          (a.negative? ^ b.negative?) ? -q : q
        end

        #: (Integer a, Integer b) -> Integer
        def srem(a, b) = a - (b * sdiv(a, b))

        # `unpack1` has no one type.
        #: (Integer w) -> untyped
        def f64(w) = [w & MASK].pack("Q<").unpack1("E")
        #: (Float f) -> untyped
        def bits(f) = [f].pack("E").unpack1("q<")
        #: (Integer w) -> Float
        def to_f64(w) = w.to_f

        # A double as a Word, saturated at the ends of the range; NaN is 0.
        #: (Float f) -> Integer
        def to_int(f)
          return 0 if f.nan?
          return SIGN - 1 if f >= SIGN
          return -SIGN if f < -SIGN

          f.to_i
        end

        #: (Integer x) -> Integer
        def ctz(x)
          u = x & MASK
          u.zero? ? 64 : (u & -u).bit_length - 1
        end

        #: (Integer x) -> Integer
        def clz(x) = 64 - (x & MASK).bit_length
        #: (Integer x) -> Integer
        def popcnt(x) = (x & MASK).digits(2).count(1)
        #: (Integer x) -> Integer
        def bswap(x)
          swapped = [x & MASK].pack("Q<").unpack1("Q>") #: Integer
          Host.signed(swapped)
        end

        #: (Float f) -> Float
        def sqrt(f) = f.negative? ? Float::NAN : Math.sqrt(f)
        #: (Float f) -> Float
        def floor(f) = integral(f) { f.floor }
        #: (Float f) -> Float
        def ceil(f) = integral(f) { f.ceil }
        #: (Float f) -> Float
        def trunc(f) = integral(f) { f.truncate }
        #: (Float f) -> Float
        def nearest(f) = integral(f) { f.round(half: :even) }
        #: (Float f) -> Float
        def fabs(f) = f.abs

        private

        #: (Integer n, Integer width) -> Integer
        def narrow(n, width)
          n &= (1 << width) - 1
          n >= (1 << (width - 1)) ? n - (1 << width) : n
        end

        # An IEEE rounding: NaN and infinities stay, and a zero keeps the
        # sign of `f`.
        #: (Float f) { () -> Integer } -> Float
        def integral(f)
          return f if f.nan? || f.infinite?

          r = yield.to_f
          r.zero? && (f.negative? || (f.zero? && 1.0 / f < 0)) ? -0.0 : r
        end
      end

      # The slots of the defs that run: an area that grows down, like a
      # stack. A def that takes a slot gets back the slots it took when it
      # returns. Each fiber has its own area (`fiber_slots`).
      SLOT_BYTES = 64 << 20

      # `kern` is the kernel module: its methods are the kernel's defs,
      # which it gets as it loads, so its type is untyped.
      attr_reader :kern #: untyped
      attr_reader :symbols #: Symbols
      attr_reader :sigs #: Hash[String, [Array[Type], Type]]
      attr_reader :slot_base #: Integer
      attr_reader :collectors #: Array[String]

      # The gate word (`Machine.gates`).
      attr_accessor :gates #: Integer

      # `files` are kernel files; `constants` sets constants that the files
      # read from a kernel file outside them; `externs` gives the address
      # of each data object of another unit (`Machine.extern`).
      #: (Array[String] files, ?symbols: Symbols, ?constants: Hash[String, untyped], ?externs: Hash[String, Integer]) -> void
      def initialize(files, symbols: Symbols.new, constants: {}, externs: {})
        @symbols = symbols
        @externs = externs
        @statics = {}
        @bytes = {}
        @callables = {}
        @def_names = {}
        @closures = {}
        @functions = {}
        @sigs = {}
        @gates = 0
        @errno = Memory.zeroed(8)
        @slot_base = Memory.zeroed(SLOT_BYTES)
        @stack_key = :"zr_host_stack_#{object_id}"
        @stacks = []
        # The rooted defs, by name, with the names of their Value locals.
        @rooted = {}
        @collecting = false
        @collectors = []
        @unit = Lower.new(files.map { |file| [File.read(file), file] }, symbols).declare_files
        @unit.declared_defs.each_value do |d|
          @sigs[d.name] = [d.params.map { |_, type| Host.type(type) }, Host.type(d.ret)]
        end
        @kern = kernel_module
        constants.each { |name, value| @kern.const_set(name, value) }
        trees = files.to_h { |file| [file, Prism.parse_file(file).value] }
        load_order(trees).each { |file| load(file) }
        bind_declarations
        @barriers = @kern.method_defined?(:zr_write_barrier)
        frames(trees.values)
      end

      # Binds the declarations that a kernel file writes as typed defs:
      # each import of `module Libc`, and each signature module's `call`.
      #: () -> void
      def bind_declarations
        @kern::Libc.bind_imports(@unit.declared_imports)
        host = self #: Host
        @unit.declared_sigs.each do |name, sig|
          mod = @kern.const_get(name, false)
          next unless mod.instance_of?(Module)

          params = sig.params.map { |type| Host.type(type) }
          ret = Host.type(sig.ret)
          mod.define_singleton_method(:call) { |at, *args| host.call_at(at, params, ret, args) }
        end
      end

      # The `Layout` of the kernel files: the superclass of each
      # `class Name < Layout`. `Name[p]` is a view at `p`, `Name.size` the
      # layout's size, and each attr of the class body a field.
      #: () -> singleton(View)
      def view_base
        host = self #: Host
        base = Class.new(View) #: singleton(View)
        base.define_singleton_method(:size) { host.layout_of(self).size }
        base.define_singleton_method(:attr_accessor) { |*names| host.view_fields(self, names, writer: true) }
        base.define_singleton_method(:attr_reader) { |*names| host.view_fields(self, names, writer: false) }
        base
      end

      # The lowering's layout of a `class Name < Layout`.
      #: (singleton(View) klass) -> Machine::Layout
      def layout_of(klass)
        name = klass.name.to_s.split("::").last.to_s
        @unit.struct_for(name) or raise ArgumentError, "#{name} is not a layout of these kernel files"
      end

      # Defines the reader, and the writer when `writer` is set, of each
      # field `names` of the layout class `klass`. A Value read is pinned
      # (`pin`), and a Value written into a cell gets the write barrier,
      # as the lowering emits them (`Function#access`).
      #: (singleton(View) klass, Array[Symbol] names, writer: bool) -> void
      def view_fields(klass, names, writer:)
        layout = layout_of(klass)
        cell = layout.name == "RBasic" || layout.fields.first&.last&.last == "RBasic"
        host = self #: Host
        kern = @kern
        names.each do |name|
          at, type_name = layout.fields.fetch(name.to_s) { raise ArgumentError, "#{layout.name} has no field #{name}" }
          if @unit.struct_for(type_name)
            klass.reader(name, ->(p) { kern.const_get(type_name, false)[p + at] })
            next
          end

          type = TYPES.fetch(type_name)
          value = type_name == "Value"
          # RBS types a method body as a proc of `self: top`, and these are
          # bodies of a View (`Memory.field_reader`).
          klass.define_method(name, Memory.field_reader(type, at, pin: value ? host : nil)) # steep:ignore ArgumentTypeMismatch
          next unless writer

          barrier = cell && value ? host : nil
          klass.define_method(:"#{name}=", Memory.field_writer(type, at, barrier: barrier)) # steep:ignore ArgumentTypeMismatch
        end
      end

      # Calls the kernel def `name`.
      # @rbs name: Symbol | String
      # @rbs *: untyped
      # @rbs return: untyped
      def call(name, *) = @kern.public_send(name, *)

      # What answers the import `name` (`Libc#answer`), as a lambda that
      # becomes the import's method: the host's errno word, the def of that
      # name, a memory function in Ruby (`Memory.function`), or the C
      # function. Each lambda reads only its own locals, as a method of
      # `Libc` runs it.
      #: (String name, Array[Type] params, Type ret) -> Proc
      def answer(name, params, ret)
        errno = @errno
        return ->(*) { errno } if ERRNO_FUNCTIONS.include?(name)

        kern = @kern
        return ->(*args) { kern.public_send(name, *args) } if kern.method_defined?(name)

        function = Fiddle::Function.new(Fiddle::Handle::DEFAULT[name], params.map(&:fiddle), ret.fiddle)
        host = self
        c = ->(*args) { host.foreign(function, params, ret, args) }
        Memory.function(name, c) || c
      end

      ERRNO_FUNCTIONS = %w[__error __errno_location].freeze #: Array[String]

      # A call through the pointer `at`: a function of the walker
      # (`callable`), a def that `Machine.addr` gave, or C code.
      #: (Integer at, Array[Type] params, Type ret, Array[untyped] args) -> untyped
      def call_at(at, params, ret, args)
        body = @callables[at]
        return walker_call(body, ret, args) if body
        if (name = @def_names[at])
          return @kern.public_send(name, *args)
        end

        function = @functions[[at, params, ret]] ||= Fiddle::Function.new(at, params.map(&:fiddle), ret.fiddle)
        foreign(function, params, ret, args)
      end

      # The address of the def `name`: a C function pointer that calls it,
      # so that C code can call it too.
      #: (String name) -> Integer
      def addr(name)
        @closures.fetch(name) do
          params, ret = @sigs.fetch(name) { raise ArgumentError, "#{name} is not a def here" }
          kern = @kern
          closure = Fiddle::Closure::BlockCaller.new(ret.fiddle, params.map(&:fiddle)) do |*args|
            values = args.zip(params).map { |arg, type| from_c(arg, type) }
            to_c(kern.public_send(name, *values), ret)
          end
          @def_names[closure.to_i] = name
          @closures[name] = closure
        end.to_i
      end

      # The name of the def whose address (`addr`) is `at`, or nil.
      #: (Integer at) -> String?
      def def_at(at) = @def_names[at]

      # An address that the kernel calls through (`Name.call`) to run
      # `body`, a Ruby proc: a function of the walker. Only the kernel
      # calls it; C cannot.
      #: (Proc body) -> Integer
      def callable(body)
        at = Memory.zeroed(16)
        @callables[at] = body
        at
      end

      # The proc at `at` that `callable` gave, or nil: the walker calls it
      # with no call through the kernel's signature.
      #: (Integer at) -> Proc?
      def body_at(at) = @callables[at]

      #: (String name, Integer size) -> Integer
      def static(name, size)
        @statics.fetch(name) { @statics[name] = Memory.zeroed(size) }
      end

      #: (String string) -> Integer
      def bytes(string)
        @bytes.fetch(string) do
          addr = Memory.zeroed(string.bytesize + 1, 1)
          Memory.write(addr, string.b)
          @bytes[string] = addr
        end
      end

      #: (String name) -> Integer
      def extern(name)
        @externs.fetch(name) { raise ArgumentError, "no data object #{name} here" }
      end

      # The machine stack of one fiber: `top` is where its next slot ends,
      # and a slot below `low` overflows. `pins` are the Values that its
      # defs hold (`pin`), and `depth` counts the walker's frames on it.
      # `roots` counts its rooted defs that run now (`Framing`), and
      # `rooted` tells whether the innermost def that can collect is one.
      # `frames` are the rooted frames of a fiber that switched away
      # (`live_roots`): only the running fiber's frames can be read.
      # @rbs skip
      Stack = Struct.new(:top, :low, :pins, :depth, :roots, :rooted, :frames)

      class Stack
        # `size` bytes of slots, rounded up to 16, below the top.
        #: (Integer size) -> Integer
        def take(size)
          slot = top - ((size + 15) & -16)
          raise "the slot area is full" if slot < low

          self.top = slot
        end
      end

      # This fiber's Stack. A thread starts on the main slot area.
      #: () -> Stack
      def stack = Thread.current[@stack_key] ||= new_stack(@slot_base + SLOT_BYTES, @slot_base)

      #: (Integer size) -> Integer
      def slot(size) = stack.take(size)

      # Where this fiber's next slot ends; a def that takes slots puts it
      # back.
      #: () -> Integer
      def slot_top = stack.top

      #: (Integer top) -> void
      def slot_top=(top)
        stack.top = top
      end

      # Gives this fiber the slot area that ends at `top`: a stack that the
      # kernel mapped for it, whose own guard page ends it.
      #: (Integer top) -> Stack
      def fiber_slots(top)
        Thread.current[@stack_key] = new_stack(top, 0)
      end

      # The walker's frames in this fiber (`Walk#frame`). Each takes ruby
      # stack too, which runs out long before the slots do.
      #: () -> Integer
      def depth = stack.depth

      #: (Integer n) -> void
      def depth=(n)
        stack.depth = n
      end

      # Keeps the Value `v` alive while the def that can collect around
      # this call runs. A collection in the kernel sees only the Values in
      # memory; a host def keeps its Values in Ruby locals, so each Value
      # it reads or makes is pinned until the def returns (`frames`). This
      # keeps more than the lowering's root frames do, never less. A rooted
      # def keeps its Values in its locals, as the lowering's root frame
      # does, so nothing is pinned while it is the innermost.
      #: (Integer v) -> Integer
      def pin(v)
        # An immediate (`zr_special_p`) is no cell, so nothing keeps it.
        return v if (v & 7) != 0 || v <= 8

        s = stack
        s.pins << v unless @collecting || s.rooted
        v
      end

      # The pins of this fiber.
      #: () -> Array[Integer]
      def pins = stack.pins

      # The collector's write barrier after a store of `value` into the
      # cell at `p`. A unit with no `zr_write_barrier` has no barrier, as
      # in the lowering (`Function#barrier`).
      #: (Integer p, Integer value) -> untyped
      def barrier(p, value)
        @kern.zr_write_barrier(p, value) if @barriers
      end

      # Marks each pinned cell and each Value local of a rooted def, and
      # runs the collection with no pinning. The running fiber's rooted
      # frames are read now; another fiber's are those it left with.
      #: () -> void
      def mark_pins
        arenas = heap_arenas
        current = stack
        @stacks.each do |s|
          s.pins.each { |v| @kern.zr_mark(v) if live?(v, arenas) }
          frames = s.equal?(current) ? live_roots : s.frames
          frames.each do |binding, names|
            names.each do |name|
              v = binding.local_variable_get(name)
              @kern.zr_mark(v) if v.is_a?(Integer) && object?(v, arenas)
            end
          end
        end
      end

      # The rooted defs (`Framing`) that run on this fiber's Ruby stack:
      # the Binding of each, with the names of its Value locals. Ruby gives
      # the frames of the running fiber only, so a fiber keeps its own as
      # it switches away (`Boot#leave`).
      #: () -> Array[[Binding, Array[Symbol]]]
      def live_roots
        return [] if stack.roots.zero?

        found = [] #: Array[[Binding, Array[Symbol]]]
        DebugInspector.open do |dc|
          dc.backtrace_locations.each_index do |i|
            next unless dc.frame_class(i).equal?(@kern)

            names = @rooted[dc.frame_iseq(i)&.label]
            binding = dc.frame_binding(i)
            found << [binding, names] if names && binding
          end
        end
        found
      end

      #: [T] () { () -> T } -> T
      def collecting
        was = @collecting
        begin
          @collecting = true
          yield
        ensure
          @collecting = was
        end
      end

      # Runs the block, a def's body, in its `frame` (`Framing`).
      #: (Framing frame) { () -> untyped } -> untyped
      def framed(frame)
        stack = self.stack
        top = stack.top
        pins = stack.pins
        mark = pins.size
        rooted = stack.rooted
        stack.roots += 1 if frame.roots
        stack.rooted = frame.roots if frame.drops
        result = begin
          yield
        ensure
          stack.top = top if frame.restores
          pins.slice!(mark, pins.size - mark) if frame.drops && pins.size > mark
          stack.roots -= 1 if frame.roots
          stack.rooted = rooted
        end
        frame.drops && frame.value ? pin(result) : result
      end

      # A call of the walker's function `body` (`call_at`). The walker pins
      # what its code holds. A rooted caller keeps the result in a local,
      # so the call leaves no pins behind for it.
      #: (Proc body, Type ret, Array[untyped] args) -> untyped
      def walker_call(body, ret, args)
        stack = self.stack
        unless stack.rooted
          result = body.call(*args)
          return ret.name == "Value" ? pin(result) : result
        end

        pins = stack.pins
        mark = pins.size
        stack.rooted = false
        begin
          body.call(*args)
        ensure
          pins.slice!(mark, pins.size - mark) if pins.size > mark
          stack.rooted = true
        end
      end

      # A call of the C function `function` (`answer`, `call_at`). C sees
      # the kernel's errno, and the kernel sees the errno that C left.
      #: (Fiddle::Function function, Array[Type] params, Type ret, Array[untyped] args) -> untyped
      def foreign(function, params, ret, args)
        values = args.zip(params).map { |arg, type| to_c(arg, type || raise(ArgumentError, "#{args.size} arguments for #{params.size}")) }
        P.write(errno_location, P.read(@errno, 4))
        result = function.call(*values)
        P.write(@errno, [Fiddle.last_error.to_i].pack("l<"))
        from_c(result, ret)
      end

      private

      #: (Integer top, Integer low) -> Stack
      def new_stack(top, low) = Stack.new(top, low, [], 0, 0, false, []).tap { |s| @stacks << s }

      # Whether `v` is a cell the heap has allocated, so the collector
      # may mark it. A pin can hold a word that is no longer one: a cell
      # that a sweep freed, or a stack image (a block's Proc) in slots
      # that other frames use now. So the flags at `v` prove nothing; the
      # cell must be in one of the heap's `arenas`, with its allocated bit
      # set. A stack image is in none, and the collector never marks one.
      #: (Integer v, Set[Integer] arenas) -> bool
      def live?(v, arenas)
        return false if @kern.zr_special_p(v)

        a = @kern.zr_arena_of(v)
        return false unless arenas.include?(a)

        i = @kern.zr_cell_index(v)
        word = Memory.word(@kern.zr_arena_allocated(a) + ((i >> 6) * 8))
        word.anybits?(@kern.zr_marks_bit(i))
      end

      # Whether the local `v` of a rooted def holds an object. A local is
      # a word of any type: a Ptr or a Word can point at a cell that is
      # allocated but not yet an object, which the lowering never roots.
      #: (Integer v, Set[Integer] arenas) -> bool
      def object?(v, arenas)
        live?(v, arenas) && @kern::RBasic[v].flags.anybits?(@kern::FL_ALLOCATED)
      end

      # The heap's arenas, by address.
      #: () -> Set[Integer]
      def heap_arenas
        h = @kern.zr_heap
        n = @kern::Heap[h].arenas
        return Set.new if n.zero?

        words = Memory.read(@kern::Heap[h].table, n * 8).unpack("Q<*") #: Array[Integer]
        words.to_set
      end

      # A fresh `Zr::Kern` with the forms a kernel file declares with.
      #: () -> Module
      def kernel_module
        # In the blocks below, self is the module, so they read `host`.
        host = self #: Host
        kern = Module.new
        kern.extend(kern)
        kern.const_set(:Machine, Intrinsics.new(self))
        kern.const_set(:Libc, Libc.new(self))
        kern.const_set(:Layout, view_base)
        kern.define_singleton_method(:inline) { |_name| nil }
        # The host runs C on one thread: an any_thread def is any def here.
        kern.define_singleton_method(:any_thread) { |_name| nil }
        kern.define_singleton_method(:collects) { |name| host.collectors << name.to_s }
        Zr.send(:remove_const, :Kern) if Zr.const_defined?(:Kern, false)
        Zr.const_set(:Kern, kern)
      end

      # The statements of a kernel file's `module Zr::Kern`.
      #: (Prism::ProgramNode tree) -> Array[Prism::node]
      def statements(tree)
        mod = tree.statements.body.find { |node| node.is_a?(Prism::ModuleNode) } #: Prism::ModuleNode?
        body = mod&.body
        raise ArgumentError, "rescue and ensure are not in the kernel subset" if body.is_a?(Prism::BeginNode)

        body&.body || []
      end

      # The files in an order that runs each constant after the constants
      # it reads. The lowering folds a constant on first use, so a file
      # may read a constant of a later file (`RBasic` of value.rb, in
      # array.rb's layouts); ruby reads it when the file runs.
      #: (Hash[String, Prism::ProgramNode] trees) -> Array[String]
      def load_order(trees)
        declared = {} #: Hash[Symbol, String]
        reads = trees.to_h do |file, tree|
          writes = statements(tree).grep(Prism::ConstantWriteNode) #: Array[Prism::ConstantWriteNode]
          names = writes.flat_map do |node|
            declared[node.name] = file
            constant_reads(node.value)
          end
          [file, names]
        end
        order = [] #: Array[String]
        trees.each_key { |file| visit_file(file, [], reads, declared, order) }
        order
      end

      # Adds `file` to `order` after the files whose constants it reads.
      # `path` is the files that wait for this one.
      #: (String file, Array[String] path, Hash[String, Array[Symbol]] reads, Hash[Symbol, String] declared, Array[String] order) -> void
      def visit_file(file, path, reads, declared, order)
        return if order.include?(file)
        raise ArgumentError, "the constants of #{path.join(" and ")} read each other" if path.include?(file)

        reads.fetch(file).filter_map { |name| declared[name] }.uniq.each do |other|
          visit_file(other, path + [file], reads, declared, order) unless other == file
        end
        order << file
      end

      #: (Prism::node node) -> Array[Symbol]
      def constant_reads(node)
        found = [] #: Array[Symbol]
        queue = [node]
        while (n = queue.shift)
          found << n.name if n.is_a?(Prism::ConstantReadNode)
          queue.concat(n.compact_child_nodes)
        end
        found
      end

      # Wraps the defs that need a frame: a def that takes a slot gives its
      # slots back when it returns, and a def that can run the collector
      # drops the pins of its body when it returns (and pins its Value
      # result for its caller). The collector runs with no pinning, and
      # marks the pins as kernel roots.
      #: (Array[Prism::ProgramNode] trees) -> void
      def frames(trees)
        all = trees.flat_map { |tree| statements(tree) }
        nodes = all.grep(Prism::DefNode) #: Array[Prism::DefNode]
        defs = nodes.to_h { |node| [node.name.to_s, node] }
        slots = defs.select { |_, node| node.slice.include?("Machine.slot(") }.keys.to_set
        collects = collecting_defs(defs)
        # In the methods below, self is the kernel, so they read `host`.
        host = self #: Host
        frames = Module.new
        (slots | collects).each do |name|
          rooted = collects.include?(name) && loops?(defs.fetch(name))
          sig = @sigs[name]
          none = [] #: Array[Integer]
          params = collects.include?(name) && !rooted && sig ? sig.first.each_index.select { |i| sig.first.fetch(i).name == "Value" } : none
          frame = Framing.new(slots.include?(name), collects.include?(name), sig&.last&.name == "Value", rooted, params)
          # The Proc takes the def's arguments; RBS types it as one with none.
          frames.define_method(name, framed_def(@kern.instance_method(name).arity, frame)) # steep:ignore ArgumentTypeMismatch
          @rooted[name] = value_locals(defs.fetch(name)).freeze if rooted
        end
        @kern.prepend(frames)
        collector = Module.new
        # `super` is the kernel's own def, which Steep cannot see.
        if defs.key?("zr_collect_kind")
          collector.define_method(:zr_collect_kind) do |*args|
            host.collecting { super(*args) } # steep:ignore UnexpectedSuper
          end
        end
        if defs.key?("zr_mark_kernel_roots")
          collector.define_method(:zr_mark_kernel_roots) do
            super() # steep:ignore UnexpectedSuper
            host.mark_pins
          end
        end
        @kern.prepend(collector)
      end

      # What a def's frame does (`frames`): it gives back the slots of its
      # body (`restores`), and drops the pins of its body (`drops`), then
      # pins a Value result (`value`) for its caller.
      #
      # A def that can collect and loops is `rooted`: a pin of each pass
      # would stay until it returns, so its locals are its roots instead,
      # as the lowering's root frame holds a def's Value locals. The
      # collector reads those locals (`value_locals`) from the def's frame
      # on the Ruby stack (`live_roots`).
      #
      # A rooted caller pins nothing, so a def that can collect and is not
      # rooted pins its Value arguments (`params`, their indices), as the
      # lowering's root frame holds a def's parameters.
      # @rbs skip
      Framing = Data.define(:restores, :drops, :value, :roots, :params)

      # The locals of the def `node` that hold Values, as the typed lowering
      # gives them root slots: each Value parameter, and each local that an
      # assignment gives a Value. A local is a Value when one of its
      # assignments is one, or is of a type this cannot tell, so no Value
      # goes unmarked. A Ptr or a Word is never marked: it can point into a
      # payload, or at a cell that is not yet an object.
      #: (Prism::DefNode node) -> Array[Symbol]
      def value_locals(node)
        d = @unit.declared_defs[node.name.to_s]
        types = {} #: Hash[Symbol, String?]
        (node.parameters&.requireds || []).each_with_index do |param, i|
          raise ArgumentError, "a machine def takes required parameters only" unless param.is_a?(Prism::RequiredParameterNode)

          types[param.name] = d ? d.params.fetch(i).last : "Value"
        end
        assigns = {} #: Hash[Symbol, Array[Prism::node]]
        queue = [node.body].compact #: Array[Prism::node]
        while (n = queue.shift)
          (assigns[n.name] ||= []) << n.value if n.is_a?(Prism::LocalVariableWriteNode)
          queue.concat(n.compact_child_nodes)
        end
        assigns.each_key { |name| types[name] ||= "Word" }
        loop do
          grown = assigns.select do |name, values|
            types[name] != "Value" && values.any? { |value| type_of(value, types).then { |type| type.nil? || type == "Value" } }
          end
          break if grown.empty?

          grown.each_key { |name| types[name] = "Value" }
        end
        types.filter_map { |name, type| name if type == "Value" }
      end

      # The type name of the kernel expression `node`, or nil when this
      # cannot tell (`value_locals`).
      #: (Prism::node? node, Hash[Symbol, String?] types) -> String?
      def type_of(node, types)
        case node
        when Prism::LocalVariableReadNode then types[node.name]
        when Prism::IntegerNode, Prism::TrueNode, Prism::FalseNode, Prism::NilNode, Prism::ConstantReadNode then "Word"
        when Prism::ParenthesesNode, Prism::StatementsNode then type_of(last_of(node), types)
        when Prism::IfNode, Prism::UnlessNode, Prism::AndNode, Prism::OrNode
          kinds = branches(node).map { |branch| branch ? type_of(branch, types) : "Word" }
          if kinds.include?("Value") then "Value"
          elsif kinds.include?(nil) then nil
          else "Word"
          end
        when Prism::CallNode then call_type(node, types)
        end
      end

      #: (Prism::node? node) -> Prism::node?
      def last_of(node)
        case node
        when Prism::ParenthesesNode then last_of(node.body)
        when Prism::StatementsNode then node.body.last
        else node
        end
      end

      # The values that a conditional answers; nil for a missing branch.
      #: (Prism::IfNode | Prism::UnlessNode | Prism::AndNode | Prism::OrNode node) -> Array[Prism::node?]
      def branches(node)
        case node
        when Prism::AndNode, Prism::OrNode then [node.left, node.right]
        when Prism::IfNode
          other = node.subsequent
          [node.statements, other.is_a?(Prism::ElseNode) ? other.statements : other]
        else [node.statements, node.else_clause&.statements]
        end
      end

      # The type of a call: a def's type, `Machine.value`, a field of a
      # view, a view (`Name[p]`), or a signature's `call`. An operator on words
      # is a word.
      #: (Prism::CallNode node, Hash[Symbol, String?] types) -> String?
      def call_type(node, types)
        recv = node.receiver
        return @unit.declared_defs[node.name.to_s]&.ret if recv.nil?
        if (layout = view_of(recv, types))
          type = layout.fields[node.name.to_s]&.last
          return type == "Value" || @unit.struct_for(type.to_s) ? type : "Word"
        end
        return recv.name.to_s if node.name == :[] && recv.is_a?(Prism::ConstantReadNode) && @unit.struct_for(recv.name.to_s)
        return "Word" unless recv.is_a?(Prism::ConstantReadNode)
        return node.name == :value ? "Value" : "Word" if recv.name == :Machine
        return "Word" if recv.name == :Libc

        @unit.declared_sigs[recv.name.to_s]&.ret
      end

      # The layout of the view that `node` is: `Name[p]`, a local that
      # holds a view, or a field of a layout type of a view. Nil for
      # anything else.
      #: (Prism::node? node, Hash[Symbol, String?] types) -> Machine::Layout?
      def view_of(node, types)
        name = case node
               when Prism::LocalVariableReadNode then types[node.name]
               when Prism::CallNode
                 if node.name == :[] && (receiver = node.receiver).is_a?(Prism::ConstantReadNode)
                   receiver.name.to_s
                 elsif (outer = view_of(node.receiver, types))
                   outer.fields[node.name.to_s]&.last
                 end
               end
        @unit.struct_for(name) if name && !TYPES.key?(name)
      end

      # Whether the def `node` has a loop.
      #: (Prism::DefNode node) -> bool
      def loops?(node)
        queue = [node.body].compact #: Array[Prism::node]
        while (n = queue.shift)
          return true if n.is_a?(Prism::WhileNode) || n.is_a?(Prism::UntilNode)

          queue.concat(n.compact_child_nodes)
        end
        false
      end

      # The method body that wraps a def of `arity` in its `frame`. Each
      # arity has its own block, which passes the def's arguments on to
      # `super` as they are: a block that takes `*args` makes an Array at
      # each call. In the frame, it pins the arguments that `frame.params`
      # names (`p0`..`p5`, each true or false).
      #
      # Each `super` is the kernel's own def, which Steep cannot see.
      #: (Integer arity, Framing frame) -> Proc
      def framed_def(arity, frame)
        host = self #: Host
        p0, p1, p2, p3, p4, p5 = Array.new(6) { |i| frame.params.include?(i) }
        case arity
        when 0 then proc { host.framed(frame) { super() } } # steep:ignore UnexpectedSuper
        when 1
          proc do |a|
            host.framed(frame) do
              host.pin(a) if p0
              super(a) # steep:ignore UnexpectedSuper
            end
          end
        when 2
          proc do |a, b|
            host.framed(frame) do
              host.pin(a) if p0
              host.pin(b) if p1
              super(a, b) # steep:ignore UnexpectedSuper
            end
          end
        when 3
          proc do |a, b, c|
            host.framed(frame) do
              host.pin(a) if p0
              host.pin(b) if p1
              host.pin(c) if p2
              super(a, b, c) # steep:ignore UnexpectedSuper
            end
          end
        when 4
          proc do |a, b, c, d|
            host.framed(frame) do
              host.pin(a) if p0
              host.pin(b) if p1
              host.pin(c) if p2
              host.pin(d) if p3
              super(a, b, c, d) # steep:ignore UnexpectedSuper
            end
          end
        when 5
          proc do |a, b, c, d, e|
            host.framed(frame) do
              host.pin(a) if p0
              host.pin(b) if p1
              host.pin(c) if p2
              host.pin(d) if p3
              host.pin(e) if p4
              super(a, b, c, d, e) # steep:ignore UnexpectedSuper
            end
          end
        when 6
          proc do |a, b, c, d, e, g|
            host.framed(frame) do
              host.pin(a) if p0
              host.pin(b) if p1
              host.pin(c) if p2
              host.pin(d) if p3
              host.pin(e) if p4
              host.pin(g) if p5
              super(a, b, c, d, e, g) # steep:ignore UnexpectedSuper
            end
          end
        else
          proc do |*args|
            host.framed(frame) do
              frame.params.each { |i| host.pin(args[i]) }
              super(*args) # steep:ignore UnexpectedSuper
            end
          end
        end
      end

      # The defs that can run the collector, as the lowering finds them
      # (`Lower#collecting_defs`): those that `collects` names, a call
      # through a pointer, and each def that calls one of those.
      #: (Hash[String, Prism::DefNode] defs) -> Set[String]
      def collecting_defs(defs)
        signatures = @unit.declared_sigs.each_key.to_set(&:to_sym)
        calls = defs.transform_values { |node| calls_in(node.body, defs, signatures) }
        set = Set.new(@collectors) #: Set[String | Symbol]
        set << :indirect
        loop do
          grown = defs.each_key.select { |name| !set.include?(name) && calls.fetch(name).any? { |c| set.include?(c) } }
          break if grown.empty?

          set.merge(grown)
        end
        # A collector that is not a def here (a raw function, which the
        # arch layer gives) makes its callers collect, but has no frame.
        set.select { |name| defs.key?(name) }.to_set #: Set[String]
      end

      #: (Prism::node? node, Hash[String, Prism::DefNode] defs, Set[Symbol] signatures) -> Array[String | Symbol]
      def calls_in(node, defs, signatures)
        found = [] #: Array[String | Symbol]
        queue = [node].compact #: Array[Prism::node]
        while (n = queue.shift)
          if n.is_a?(Prism::CallNode)
            found << n.name.to_s if n.receiver.nil? && (defs.key?(n.name.to_s) || @collectors.include?(n.name.to_s))
            receiver = n.receiver
            found << :indirect if n.name == :call && receiver.is_a?(Prism::ConstantReadNode) && signatures.include?(receiver.name)
          end
          queue.concat(n.compact_child_nodes)
        end
        found
      end

      # This thread's errno, which a C function reads and sets.
      #: () -> Integer
      def errno_location
        @errno_location ||= begin
          name = RUBY_PLATFORM.include?("darwin") ? "__error" : "__errno_location"
          Fiddle::Function.new(Fiddle::Handle::DEFAULT[name], [], Fiddle::TYPE_VOIDP).call.to_i
        end
      end

      #: (untyped value, Type type) -> untyped
      def to_c(value, type)
        case type.name
        when "Bool" then value ? 1 : 0
        when "Void" then nil
        when "F64" then value
        else Host.bits(value)
        end
      end

      #: (untyped value, Type type) -> untyped
      def from_c(value, type)
        case type.name
        when "Ptr" then Host.unsigned(value.to_i)
        when "Value" then pin(value)
        when "Bool" then value != 0
        when "Void" then nil
        else value
        end
      end
    end
  end
end
