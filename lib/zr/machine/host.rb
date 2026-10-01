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
      # Fiddle, its `pack` format (`packing`), and its IO::Buffer types for
      # a load (`loads`) and a store (`stores`). A store takes a value of the signed or the unsigned range
      # alike: `pack` and an unsigned IO::Buffer type take either.
      Type = Data.define(:name, :size, :fiddle, :packing, :loads, :stores) do
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
        @stacks = []
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

      # The proc at `at` that `callable` gave, or nil: the walker calls it
      # with no call through the kernel's signature.
      def body_at(at) = @callables[at]

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
      # `roots` are the Bindings of its rooted defs (`Framing`), and
      # `rooted` tells whether the innermost def that can collect is one.
      Stack = Struct.new(:top, :low, :pins, :depth, :roots, :rooted) do
        # `size` bytes of slots, rounded up to 16, below the top.
        def take(size)
          slot = top - ((size + 15) & -16)
          raise "the slot area is full" if slot < low

          self.top = slot
        end
      end

      # This fiber's Stack. A thread starts on the main slot area.
      def stack = Thread.current[@stack_key] ||= new_stack(@slot_base + SLOT_BYTES, @slot_base)

      def slot(size) = stack.take(size)

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
      # keeps more than the lowering's root frames do, never less. A rooted
      # def keeps its Values in its locals, as the lowering's root frame
      # does, so nothing is pinned while it is the innermost.
      def pin(v)
        s = stack
        s.pins << v unless @collecting || s.rooted
        v
      end

      # The pins of this fiber.
      def pins = stack.pins

      # The collector's write barrier after a store of `value` into the
      # cell at `p`.
      def barrier(p, value)
        @kern.zr_write_barrier(p, value)
      end

      # Marks each pinned cell and each Value local of a rooted def, and
      # runs the collection with no pinning.
      def mark_pins
        arenas = heap_arenas
        @stacks.each do |s|
          s.pins.each { |v| @kern.zr_mark(v) if live?(v, arenas) }
          s.roots.each do |binding, names|
            names&.each do |name|
              v = binding.local_variable_get(name)
              @kern.zr_mark(v) if v.is_a?(Integer) && object?(v, arenas)
            end
          end
        end
      end

      def collecting
        was = @collecting
        @collecting = true
        yield
      ensure
        @collecting = was
      end

      # Runs the block, a def's body, in its `frame` (`Framing`).
      # A rooted def's Binding takes its place in `roots` when the def
      # starts (`frames`).
      def framed(frame)
        stack = self.stack
        top = stack.top
        pins = stack.pins
        mark = pins.size
        rooted = stack.rooted
        stack.roots << nil if frame.roots
        stack.rooted = frame.roots if frame.drops
        result = begin
          yield
        ensure
          stack.top = top if frame.restores
          pins.slice!(mark, pins.size - mark) if frame.drops
          stack.roots.pop if frame.roots
          stack.rooted = rooted
        end
        frame.drops && frame.value ? pin(result) : result
      end

      # A call of the walker's function `body` (`call_at`). The walker pins
      # what its code holds. A rooted caller keeps the result in a local,
      # so the call leaves no pins behind for it.
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
          pins.slice!(mark, pins.size - mark)
          stack.rooted = true
        end
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

      def new_stack(top, low) = Stack.new(top, low, [], 0, [], false).tap { |s| @stacks << s }

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

      # Whether the local `v` of a rooted def holds an object. A local is
      # a word of any type: a Ptr or a Word can point at a cell that is
      # allocated but not yet an object, which the lowering never roots.
      def object?(v, arenas)
        live?(v, arenas) && @kern::RBasic.flags(v).anybits?(@kern::FL_ALLOCATED)
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
          rooted = collects.include?(name) && loops?(defs.fetch(name))
          sig = @sigs[name]
          params = collects.include?(name) && !rooted && sig ? sig.first.each_index.select { |i| sig.first[i].name == "Value" } : []
          frame = Framing.new(slots.include?(name), collects.include?(name), sig&.last&.name == "Value", rooted, params)
          body = @kern.instance_method(name)
          frames.define_method(name, &framed_def(body.arity, frame))
          next unless rooted

          names = value_locals(defs.fetch(name)).freeze
          TracePoint.new(:call) { |tp| host.stack.roots[-1] = [tp.binding, names] }.enable(target: body)
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

      # What a def's frame does (`frames`): it gives back the slots of its
      # body (`restores`), and drops the pins of its body (`drops`), then
      # pins a Value result (`value`) for its caller.
      #
      # A def that can collect and loops is `rooted`: a pin of each pass
      # would stay until it returns, so its locals are its roots instead,
      # as the lowering's root frame holds a def's Value locals. The
      # collector marks those locals (`value_locals`) through its Binding.
      #
      # A rooted caller pins nothing, so a def that can collect and is not
      # rooted pins its Value arguments (`params`, their indices), as the
      # lowering's root frame holds a def's parameters.
      Framing = Data.define(:restores, :drops, :value, :roots, :params)

      # The locals of the def `node` that hold Values, as the typed lowering
      # gives them root slots: each Value parameter, and each local that an
      # assignment gives a Value. A local is a Value when one of its
      # assignments is one, or is of a type this cannot tell, so no Value
      # goes unmarked. A Ptr or a Word is never marked: it can point into a
      # payload, or at a cell that is not yet an object.
      def value_locals(node)
        sig = @sigs[node.name.to_s]
        types = {}
        (node.parameters&.requireds || []).each_with_index { |param, i| types[param.name] = sig ? sig.first[i].name : "Value" }
        assigns = Hash.new { |h, name| h[name] = [] }
        queue = [node.body].compact
        while (n = queue.shift)
          assigns[n.name] << n.value if n.is_a?(Prism::LocalVariableWriteNode)
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
        when Prism::CallNode then call_type(node)
        end
      end

      def last_of(node)
        node = node.body while node.is_a?(Prism::ParenthesesNode)
        node.is_a?(Prism::StatementsNode) ? node.body.last : node
      end

      # The values that a conditional answers; nil for a missing branch.
      def branches(node)
        case node
        when Prism::AndNode, Prism::OrNode then [node.left, node.right]
        when Prism::IfNode
          other = node.subsequent
          [node.statements, other.is_a?(Prism::ElseNode) ? other.statements : other]
        else [node.statements, node.else_clause&.statements]
        end
      end

      # The type of a call: a def's sig, `Machine.value`, a layout field,
      # or a signature's `call`. An operator on words is a word.
      def call_type(node)
        recv = node.receiver
        return @sigs[node.name.to_s]&.last&.name if recv.nil?
        return "Word" unless recv.is_a?(Prism::ConstantReadNode)
        return node.name == :value ? "Value" : "Word" if recv.name == :Machine
        return "Word" if recv.name == :Libc

        thing = @kern.const_defined?(recv.name, false) ? @kern.const_get(recv.name, false) : nil
        case thing
        when Layout
          type = thing.layout_fields[node.name]&.last
          type.respond_to?(:name) ? type.name : "Word"
        when Fn then thing.ret.name
        end
      end

      # Whether the def `node` has a loop.
      def loops?(node)
        queue = [node.body].compact
        while (n = queue.shift)
          return true if n.is_a?(Prism::WhileNode) || n.is_a?(Prism::UntilNode)

          queue.concat(n.compact_child_nodes)
        end
        false
      end

      # The method body that wraps a def of `arity` in its `frame`. Each
      # arity has its own block, which passes the def's arguments on to
      # `super` as they are: a block that takes `*args` makes an Array at
      # each call.
      def framed_def(arity, frame)
        host = self
        unless frame.params.empty?
          params = frame.params
          return proc do |*args|
            host.framed(frame) do
              params.each { |i| host.pin(args[i]) }
              super(*args)
            end
          end
        end

        case arity
        when 0 then proc { host.framed(frame) { super() } }
        when 1 then proc { |a| host.framed(frame) { super(a) } }
        when 2 then proc { |a, b| host.framed(frame) { super(a, b) } }
        when 3 then proc { |a, b, c| host.framed(frame) { super(a, b, c) } }
        when 4 then proc { |a, b, c, d| host.framed(frame) { super(a, b, c, d) } }
        when 5 then proc { |a, b, c, d, e| host.framed(frame) { super(a, b, c, d, e) } }
        when 6 then proc { |a, b, c, d, e, g| host.framed(frame) { super(a, b, c, d, e, g) } }
        else proc { |*args| host.framed(frame) { super(*args) } }
        end
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
