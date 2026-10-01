# frozen_string_literal: true

require "fiddle"
require_relative "../prism"
require_relative "description"
require_relative "host/memory"

module Zr
  module Machine
    # The kernel on CRuby (A7). The kernel's files are plain Ruby in
    # `module Zr::Kern` (A6), and a host loads them into this ruby: each
    # `def` is a method of the module, and the forms that a build lowers
    # (`Machine.*`, `Libc.*`, `layout`, `fn`) are objects here that act on
    # the process's real memory through Fiddle.
    #
    # The values are the type model of A6: an I8, I32, Word or Value is an
    # Integer in the signed range of its width, a Ptr an Integer in
    # [0, 2**64), a Bool true or false, and an F64 a Float. The lowering
    # refuses each form whose meaning on this model differs from the
    # native one, so a def runs here as it runs in a binary.
    #
    # Only one kernel is `Zr::Kern` at a time; a new Host replaces it. A
    # build never loads this file.
    class Host
      WORD = 1 << 64
      MASK = WORD - 1
      SIGN = 1 << 63

      # A type of the kernel: its name, its size in memory, its type for
      # Fiddle, its `pack` format, and its IO::Buffer types for a load and
      # a store. A store takes a value of the signed or the unsigned range
      # alike: `pack` and an unsigned IO::Buffer type take either.
      Type = Data.define(:name, :size, :fiddle, :format, :load, :store) do
        def inspect = name
      end
      TYPES = [
        ["Word", 8, Fiddle::TYPE_LONG_LONG, "q<", :s64, :u64], ["Value", 8, Fiddle::TYPE_LONG_LONG, "q<", :s64, :u64],
        ["Ptr", 8, Fiddle::TYPE_VOIDP, "Q<", :u64, :u64], ["I32", 4, Fiddle::TYPE_INT, "l<", :s32, :u32],
        ["I8", 1, Fiddle::TYPE_CHAR, "c", :S8, :U8], ["Bool", 1, Fiddle::TYPE_CHAR, "C", :U8, :U8],
        ["F64", 8, Fiddle::TYPE_DOUBLE, "E", :f64, :f64], ["Void", 0, Fiddle::TYPE_VOID, nil, nil, nil]
      ].to_h { |row| [row.first, Type.new(*row)] }.freeze

      # The bits of `n` as a signed 64-bit Integer. Most words are in the
      # range already, and the test for that makes no Bignum.
      def self.signed(n)
        return n if n.bit_length < 64

        n &= MASK
        n < SIGN ? n : n - WORD
      end

      # The bits of `n` as an unsigned 64-bit Integer.
      def self.unsigned(n) = !n.negative? && n.bit_length <= 64 ? n : n & MASK

      # An Integer, or a Bool as 1 or 0.
      def self.bits(value)
        case value
        when true then 1
        when false, nil then 0
        else value
        end
      end

      # `Name = layout field: Type, ...`: each field at its natural
      # alignment, a struct field embedded in place. It answers
      # `Name.size`, `Name.field(p)` and `Name.set_field(p, value)`; the
      # reader of an embedded struct answers its address.
      #
      # A field may be named `size`: `Name.size` with no pointer is still
      # the layout's size, as in the lowering. So the layout's own readers
      # have names no field has.
      #
      # A Value read from a field is pinned (`Host#pin`), and a Value
      # written to a field of a cell gets the collector's write barrier, as
      # the lowering emits it (`Function#barrier`).
      class Layout
        attr_reader :layout_fields, :layout_size, :layout_align

        def initialize(fields, host = nil)
          @host = host
          off = 0
          @layout_align = 1
          @layout_fields = fields.to_h do |name, type|
            size, align = type.is_a?(Layout) ? [type.layout_size, type.layout_align] : [type.size, type.size]
            raise ArgumentError, "a field cannot be Void" if size.zero?

            off += (-off) % align
            @layout_align = [@layout_align, align].max
            at = off
            off += size
            [name.to_s, [at, type]]
          end
          @layout_size = off + ((-off) % @layout_align)
          @layout_fields.each { |name, (at, type)| accessors(name, at, type) }
        end

        def size(*pointer)
          pointer.empty? ? @layout_size : raise(NoMethodError, "no field size")
        end

        # Marks this layout as a cell's: a store of a Value into one of its
        # fields runs the write barrier of the cell at `p`.
        def cell!
          host = @host
          @layout_fields.each do |name, (at, type)|
            next unless type.is_a?(Type) && type.name == "Value"

            store = Memory.writer(type, at)
            define_singleton_method(:"set_#{name}") do |p, value|
              store.call(p, value)
              host.barrier(p, value)
            end
          end
        end

        private

        def accessors(name, at, type)
          host = @host
          reader = if type.is_a?(Layout)
                     ->(p) { p + at }
                   elsif type.name == "Value" && host
                     load = Memory.reader(type, at)
                     ->(p) { host.pin(load.call(p)) }
                   else
                     Memory.reader(type, at)
                   end
          define_singleton_method(:"set_#{name}", &Memory.writer(type, at)) unless type.is_a?(Layout)
          if name == "size"
            define_singleton_method(:size) { |*pointer| pointer.empty? ? @layout_size : reader.call(pointer.first) }
          else
            define_singleton_method(name, &reader)
          end
        end
      end

      # `Name = fn [types] => type`: a call through a pointer,
      # `Name.call(p, ...)`.
      class Fn
        attr_reader :params, :ret

        def initialize(host, params, ret)
          @host = host
          @params = params
          @ret = ret
        end

        def call(at, *args) = @host.call_at(at, @params, @ret, args)
      end

      # `Libc`: `Libc.import :name, [types] => type` declares a C function,
      # and `Libc.name(...)` calls it. A def of the same name answers the
      # import, as the lowering's `answers_import` says.
      #
      # The first call of an import finds what answers it (`Host#answer`),
      # and the import's method becomes that: later calls go straight to
      # it. The kernel's own defs are all loaded by then, and the host's
      # layers prepended.
      class Libc
        def initialize(host)
          @host = host
          @imports = {}
        end

        def import(name, signature)
          pair = signature.find { |key, _| key.is_a?(Array) } or raise ArgumentError, "an import is `Libc.import :name, [types] => type`"
          params, ret = pair
          @imports[name.to_s] = [params, ret]
          define_singleton_method(name) { |*args| answer(name, params, ret).call(*args) }
        end

        attr_reader :imports

        private

        def answer(name, params, ret)
          body = @host.answer(name.to_s, params, ret)
          define_singleton_method(name, &body)
          body
        end
      end

      # The intrinsics, `Machine.*`, as the lowering defines them
      # (`Function#intrinsic`). A name's id, static and address do not
      # change, so each is found once.
      class Intrinsics
        def initialize(host)
          @host = host
          @ids = {}
          @statics = {}
          @addrs = {}
          @bytes = {}.compare_by_identity
        end

        def id(name) = @ids[name] ||= @host.symbols.id(name.to_s)
        def bytesize(string) = string.bytesize
        def bytes(string) = @bytes[string] ||= @host.bytes(string)
        def extern(name) = @host.extern(name.to_s)
        def static(name, size) = @statics[name] ||= @host.static(name.to_s, size)
        def slot(size) = @host.slot(size)
        def addr(name) = @addrs[name] ||= @host.addr(name.to_s)

        LOAD64 = Memory.reader(TYPES["Word"], 0)
        LOAD32 = Memory.reader(TYPES["I32"], 0)
        LOAD8 = Memory.reader(TYPES["I8"], 0)
        STORE64 = Memory.writer(TYPES["Word"], 0)
        STORE32 = Memory.writer(TYPES["I32"], 0)
        STORE8 = Memory.writer(TYPES["I8"], 0)

        def load64(p, off) = LOAD64.call(p + off)
        def load32(p, off) = LOAD32.call(p + off)
        def load8(p, off) = LOAD8.call(p + off)
        def store64(p, off, value) = STORE64.call(p + off, value)
        def store32(p, off, value) = STORE32.call(p + off, value)
        def store8(p, off, value) = STORE8.call(p + off, value)

        def gates = @host.gates
        def gates_set(word) = @host.gates = word
        def gates_enter = nil

        # A Word of `x`: an Integer in the signed range is one already.
        def word(x) = x.is_a?(Integer) && x.bit_length < 64 ? x : Host.signed(Host.bits(x))
        def sword(x) = word(x)
        def value(x) = @host.pin(word(x))
        def ptr(x) = Host.unsigned(Host.bits(x))
        def u8(x) = x & 0xFF
        def u32(x) = x & 0xFFFF_FFFF
        def i8(x) = narrow(Host.bits(x), 8)
        def i32(x) = narrow(Host.bits(x), 32)

        def add_wrap(a, b) = Host.signed(a + b)
        def sub_wrap(a, b) = Host.signed(a - b)
        def mul_wrap(a, b) = Host.signed(a * b)
        def shl_wrap(a, b) = Host.signed(a << (b & 63))
        def uadd_wrap(a, b) = Host.unsigned(a + b)
        def usub_wrap(a, b) = Host.unsigned(a - b)
        def umul_wrap(a, b) = Host.unsigned(a * b)
        def ushl_wrap(a, b) = Host.unsigned(a << (b & 63))

        # Division that truncates toward zero, as C's.
        def sdiv(a, b)
          q = a.abs / b.abs
          (a.negative? ^ b.negative?) ? -q : q
        end

        def srem(a, b) = a - (b * sdiv(a, b))

        def f64(w) = [w & MASK].pack("Q<").unpack1("E")
        def bits(f) = [f].pack("E").unpack1("q<")
        def to_f64(w) = w.to_f

        # A double as a Word, saturated at the ends of the range; NaN is 0.
        def to_int(f)
          return 0 if f.nan?
          return SIGN - 1 if f >= SIGN
          return -SIGN if f < -SIGN

          f.to_i
        end

        def ctz(x)
          u = x & MASK
          u.zero? ? 64 : (u & -u).bit_length - 1
        end

        def clz(x) = 64 - (x & MASK).bit_length
        def popcnt(x) = (x & MASK).digits(2).count(1)
        def bswap(x) = Host.signed([x & MASK].pack("Q<").unpack1("Q>"))

        def sqrt(f) = f.negative? ? Float::NAN : Math.sqrt(f)
        def floor(f) = integral(f) { f.floor }
        def ceil(f) = integral(f) { f.ceil }
        def trunc(f) = integral(f) { f.truncate }
        def nearest(f) = integral(f) { f.round(half: :even) }
        def fabs(f) = f.abs

        private

        def narrow(n, width)
          n &= (1 << width) - 1
          n >= (1 << (width - 1)) ? n - (1 << width) : n
        end

        # An IEEE rounding: NaN and infinities stay, and a zero keeps the
        # sign of `f`.
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

      attr_reader :kern, :symbols, :sigs, :slot_base, :collectors

      # The gate word (`Machine.gates`).
      attr_accessor :gates

      # `files` are kernel files; `constants` sets constants that the files
      # read from a kernel file outside them; `externs` gives the address
      # of each data object of another unit (`Machine.extern`).
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
        @all_pins = []
        @collecting = false
        @collectors = []
        @kern = kernel_module
        constants.each { |name, value| @kern.const_set(name, value) }
        trees = files.to_h { |file| [file, Prism.parse_file(file).value] }
        load_order(trees).each { |file| load(file) }
        cells!
        frames(trees.values)
      end

      # Calls the kernel def `name`.
      def call(name, *) = @kern.public_send(name, *)

      # What answers the import `name` (`Libc#answer`), as a lambda that
      # becomes the import's method: the host's errno word, the def of that
      # name, a memory function in Ruby (`Memory.function`), or the C
      # function. Each lambda reads only its own locals, as a method of
      # `Libc` runs it.
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

      ERRNO_FUNCTIONS = %w[__error __errno_location].freeze

      # A call through the pointer `at`: a function of the walker
      # (`callable`), a def that `Machine.addr` gave, or C code.
      def call_at(at, params, ret, args)
        if (body = @callables[at])
          result = body.call(*args)
          return ret.name == "Value" ? pin(result) : result
        end
        if (name = @def_names[at])
          return @kern.public_send(name, *args)
        end

        function = @functions[[at, params, ret]] ||= Fiddle::Function.new(at, params.map(&:fiddle), ret.fiddle)
        foreign(function, params, ret, args)
      end

      # The address of the def `name`: a C function pointer that calls it,
      # so that C code can call it too.
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
      def def_at(at) = @def_names[at]

      # An address that the kernel calls through (`Name.call`) to run
      # `body`, a Ruby proc: a function of the walker. Only the kernel
      # calls it; C cannot.
      def callable(body)
        at = Memory.zeroed(16)
        @callables[at] = body
        at
      end

      def static(name, size)
        @statics.fetch(name) { @statics[name] = Memory.zeroed(size) }
      end

      def bytes(string)
        @bytes.fetch(string) do
          addr = Memory.zeroed(string.bytesize + 1, 1)
          Memory.write(addr, string.b)
          @bytes[string] = addr
        end
      end

      def extern(name)
        @externs.fetch(name) { raise ArgumentError, "no data object #{name} here" }
      end

      # The machine stack of one fiber: `top` is where its next slot ends,
      # and a slot below `low` overflows. `pins` are the Values that its
      # defs hold (`pin`), and `depth` counts the walker's frames on it.
      Stack = Struct.new(:top, :low, :pins, :depth)

      # This fiber's Stack. A thread starts on the main slot area.
      def stack = Thread.current[@stack_key] ||= new_stack(@slot_base + SLOT_BYTES, @slot_base)

      def slot(size)
        s = stack
        top = s.top - ((size + 15) & -16)
        raise "the slot area is full" if top < s.low

        s.top = top
      end

      # Where this fiber's next slot ends; a def that takes slots puts it
      # back.
      def slot_top = stack.top

      def slot_top=(top)
        stack.top = top
      end

      # Gives this fiber the slot area that ends at `top`: a stack that the
      # kernel mapped for it, whose own guard page ends it.
      def fiber_slots(top)
        Thread.current[@stack_key] = new_stack(top, 0)
      end

      # The walker's frames in this fiber (`Walk#frame`). Each takes ruby
      # stack too, which runs out long before the slots do.
      def depth = stack.depth

      def depth=(n)
        stack.depth = n
      end

      # Keeps the Value `v` alive while the def that can collect around
      # this call runs. A collection in the kernel sees only the Values in
      # memory; a host def keeps its Values in Ruby locals, so each Value
      # it reads or makes is pinned until the def returns (`frames`). This
      # keeps more than the lowering's root frames do, never less.
      def pin(v)
        stack.pins << v unless @collecting
        v
      end

      # The pins of this fiber.
      def pins = stack.pins

      # The collector's write barrier after a store of `value` into the
      # cell at `p`.
      def barrier(p, value)
        @kern.zr_write_barrier(p, value)
      end

      # Marks each pinned cell, and runs the collection with no pinning.
      def mark_pins
        arenas = heap_arenas
        @all_pins.each do |list|
          list.each { |v| @kern.zr_mark(v) if live?(v, arenas) }
        end
      end

      def collecting
        was = @collecting
        @collecting = true
        yield
      ensure
        @collecting = was
      end

      # A call of the C function `function` (`answer`, `call_at`). C sees
      # the kernel's errno, and the kernel sees the errno that C left.
      def foreign(function, params, ret, args)
        values = args.zip(params).map { |arg, type| to_c(arg, type) }
        P.write(errno_location, P.read(@errno, 4))
        result = function.call(*values)
        P.write(@errno, [Fiddle.last_error.to_i].pack("l<"))
        from_c(result, ret)
      end

      private

      def new_stack(top, low) = Stack.new(top, low, [], 0).tap { |s| @all_pins << s.pins }

      # Whether `v` is a cell the heap has allocated, so the collector
      # may mark it. A pin can hold a word that is no longer one: a cell
      # that a sweep freed, or a stack image (a block's Proc) in slots
      # that other frames use now. So the flags at `v` prove nothing; the
      # cell must be in one of the heap's `arenas`, with its allocated bit
      # set. A stack image is in none, and the collector never marks one.
      def live?(v, arenas)
        return false if @kern.zr_special_p(v)

        a = @kern.zr_arena_of(v)
        return false unless arenas.include?(a)

        i = @kern.zr_cell_index(v)
        word = Memory.word(@kern.zr_arena_allocated(a) + ((i >> 6) * 8))
        word.anybits?(@kern.zr_marks_bit(i))
      end

      # The heap's arenas, by address.
      def heap_arenas
        h = @kern.zr_heap
        n = @kern::Heap.arenas(h)
        n.zero? ? Set.new : Memory.read(@kern::Heap.table(h), n * 8).unpack("Q<*").to_set
      end

      # Gives each layout of a cell (RBasic, and each layout that starts
      # with it) the write barrier, as the lowering's `cell?` does.
      def cells!
        return unless @kern.const_defined?(:RBasic, false)

        basic = @kern::RBasic
        @kern.constants(false).each do |name|
          layout = @kern.const_get(name)
          next unless layout.is_a?(Layout)

          first = layout.layout_fields.first&.last&.last
          layout.cell! if layout.equal?(basic) || first.equal?(basic)
        end
      end

      # A fresh `Zr::Kern` with the forms a kernel file declares with.
      def kernel_module
        host = self
        kern = Module.new
        kern.extend(kern)
        TYPES.each { |name, type| kern.const_set(name, type) }
        kern.const_set(:Machine, Intrinsics.new(self))
        kern.const_set(:Libc, Libc.new(self))
        pending = nil
        kern.define_singleton_method(:layout) { |**fields| Layout.new(fields, host) }
        kern.define_singleton_method(:fn) { |signature| Fn.new(host, *signature.first) }
        kern.define_singleton_method(:sig) { |signature| pending = signature.first }
        kern.define_singleton_method(:inline) { |_name| nil }
        kern.define_singleton_method(:collects) { |name| host.collectors << name.to_s }
        kern.define_singleton_method(:raw) { |_name, _signature| nil }
        kern.define_singleton_method(:method_added) do |name|
          host.sigs[name.to_s] = pending if pending
          pending = nil
        end
        Zr.send(:remove_const, :Kern) if Zr.const_defined?(:Kern, false)
        Zr.const_set(:Kern, kern)
      end

      # The statements of a kernel file's `module Zr::Kern`.
      def statements(tree)
        mod = tree.statements.body.find { |node| node.is_a?(Prism::ModuleNode) }
        mod&.body&.body || []
      end

      # The files in an order that runs each constant after the constants
      # it reads. The lowering folds a constant on first use, so a file
      # may read a constant of a later file (`RBasic` of value.rb, in
      # array.rb's layouts); ruby reads it when the file runs.
      def load_order(trees)
        declared = {}
        reads = trees.to_h do |file, tree|
          names = statements(tree).grep(Prism::ConstantWriteNode).flat_map do |node|
            declared[node.name] = file
            constant_reads(node.value)
          end
          [file, names]
        end
        order = []
        visit = lambda do |file, path|
          next if order.include?(file)
          raise ArgumentError, "the constants of #{path.join(" and ")} read each other" if path.include?(file)

          reads.fetch(file).filter_map { |name| declared[name] }.uniq.each { |other| visit.call(other, path + [file]) unless other == file }
          order << file
        end
        trees.each_key { |file| visit.call(file, []) }
        order
      end

      def constant_reads(node)
        found = []
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
      def frames(trees)
        defs = trees.flat_map { |tree| statements(tree).grep(Prism::DefNode) }.to_h { |node| [node.name.to_s, node] }
        slots = defs.select { |_, node| node.slice.include?("Machine.slot(") }.keys.to_set
        collects = collecting_defs(defs)
        host = self
        frames = Module.new
        (slots | collects).each do |name|
          restores = slots.include?(name)
          drops = collects.include?(name)
          value = @sigs[name]&.last&.name == "Value"
          frames.define_method(name) do |*args|
            stack = host.stack
            top = stack.top
            mark = stack.pins.size
            result = begin
              super(*args)
            ensure
              stack.top = top if restores
              stack.pins.slice!(mark..) if drops
            end
            drops && value ? host.pin(result) : result
          end
        end
        @kern.prepend(frames)
        collector = Module.new
        collector.define_method(:zr_collect_kind) { |*args| host.collecting { super(*args) } } if defs.key?("zr_collect_kind")
        if defs.key?("zr_mark_kernel_roots")
          collector.define_method(:zr_mark_kernel_roots) do
            super()
            host.mark_pins
          end
        end
        @kern.prepend(collector)
      end

      # The defs that can run the collector, as the lowering finds them
      # (`Lower#collecting_defs`): those that `collects` names, a call
      # through a pointer, and each def that calls one of those.
      def collecting_defs(defs)
        signatures = @kern.constants(false).select { |name| @kern.const_get(name).is_a?(Fn) }.to_set
        calls = defs.transform_values { |node| calls_in(node.body, defs, signatures) }
        set = @collectors.to_set << :indirect
        loop do
          grown = defs.each_key.select { |name| !set.include?(name) && calls.fetch(name).any? { |c| set.include?(c) } }
          break if grown.empty?

          set.merge(grown)
        end
        set.delete(:indirect)
        set
      end

      def calls_in(node, defs, signatures)
        found = []
        queue = [node].compact
        while (n = queue.shift)
          if n.is_a?(Prism::CallNode)
            found << n.name.to_s if n.receiver.nil? && defs.key?(n.name.to_s)
            found << :indirect if n.name == :call && n.receiver.is_a?(Prism::ConstantReadNode) && signatures.include?(n.receiver.name)
          end
          queue.concat(n.compact_child_nodes)
        end
        found
      end

      # This thread's errno, which a C function reads and sets.
      def errno_location
        @errno_location ||= begin
          name = RUBY_PLATFORM.include?("darwin") ? "__error" : "__errno_location"
          Fiddle::Function.new(Fiddle::Handle::DEFAULT[name], [], Fiddle::TYPE_VOIDP).call.to_i
        end
      end

      def to_c(value, type)
        case type.name
        when "Bool" then value ? 1 : 0
        when "Void" then nil
        when "F64" then value
        else Host.bits(value)
        end
      end

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
