# frozen_string_literal: true

require "fiddle"
require_relative "../prism"
require_relative "description"

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

      # A type of the kernel: its name, its size in memory and its type for
      # Fiddle.
      Type = Data.define(:name, :size, :fiddle) do
        def inspect = name
      end
      TYPES = [
        Type.new("Word", 8, Fiddle::TYPE_LONG_LONG), Type.new("Value", 8, Fiddle::TYPE_LONG_LONG),
        Type.new("Ptr", 8, Fiddle::TYPE_VOIDP), Type.new("I32", 4, Fiddle::TYPE_INT), Type.new("I8", 1, Fiddle::TYPE_CHAR),
        Type.new("Bool", 1, Fiddle::TYPE_CHAR), Type.new("F64", 8, Fiddle::TYPE_DOUBLE), Type.new("Void", 0, Fiddle::TYPE_VOID)
      ].to_h { |t| [t.name, t] }.freeze

      # The bits of `n` as a signed 64-bit Integer.
      def self.signed(n) = (n & SIGN).zero? ? n & MASK : (n & MASK) - WORD

      # The real memory of this process. An address is an Integer.
      module Memory
        module_function

        def read(addr, len) = Fiddle::Pointer.read(addr, len)
        def write(addr, bytes) = Fiddle::Pointer.write(addr, bytes)

        def fetch(type, addr)
          case type.name
          when "Word", "Value" then read(addr, 8).unpack1("q<")
          when "Ptr" then read(addr, 8).unpack1("Q<")
          when "I32" then read(addr, 4).unpack1("l<")
          when "I8" then read(addr, 1).unpack1("c")
          when "Bool" then read(addr, 1).getbyte(0) != 0
          when "F64" then read(addr, 8).unpack1("E")
          else raise ArgumentError, "no load of a #{type.name}"
          end
        end

        def put(type, addr, value)
          case type.name
          when "Word", "Value", "Ptr" then write(addr, [Host.bits(value) & MASK].pack("Q<"))
          when "I32" then write(addr, [Host.bits(value) & 0xFFFF_FFFF].pack("L<"))
          when "I8", "Bool" then write(addr, [Host.bits(value) & 0xFF].pack("C"))
          when "F64" then write(addr, [value].pack("E"))
          else raise ArgumentError, "no store of a #{type.name}"
          end
        end

        # `size` zeroed bytes that stay until the process ends.
        def zeroed(size, align = 16)
          addr = Fiddle.malloc(size + align)
          addr += (-addr) % align
          write(addr, "\0".b * size) if size.positive?
          addr
        end
      end

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
      class Layout
        attr_reader :layout_fields, :layout_size, :layout_align

        def initialize(fields)
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

        private

        def accessors(name, at, type)
          reader = if type.is_a?(Layout)
                     ->(p) { p + at }
                   else
                     define_singleton_method(:"set_#{name}") { |p, value| Memory.put(type, p + at, value) }
                     ->(p) { Memory.fetch(type, p + at) }
                   end
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
      class Libc
        def initialize(host)
          @host = host
          @imports = {}
        end

        def import(name, signature)
          pair = signature.find { |key, _| key.is_a?(Array) } or raise ArgumentError, "an import is `Libc.import :name, [types] => type`"
          params, ret = pair
          @imports[name.to_s] = [params, ret]
          host = @host
          define_singleton_method(name) { |*args| host.libc(name.to_s, params, ret, args) }
        end

        attr_reader :imports
      end

      # The intrinsics, `Machine.*`, as the lowering defines them
      # (`Function#intrinsic`).
      class Intrinsics
        def initialize(host) = @host = host

        def id(name) = @host.symbols.id(name.to_s)
        def bytesize(string) = string.bytesize
        def bytes(string) = @host.bytes(string)
        def extern(name) = @host.extern(name.to_s)
        def static(name, size) = @host.static(name.to_s, size)
        def slot(size) = @host.slot(size)
        def addr(name) = @host.addr(name.to_s)

        def load64(p, off) = Memory.fetch(TYPES["Word"], p + off)
        def load32(p, off) = Memory.fetch(TYPES["I32"], p + off)
        def load8(p, off) = Memory.fetch(TYPES["I8"], p + off)
        def store64(p, off, value) = Memory.put(TYPES["Word"], p + off, value)
        def store32(p, off, value) = Memory.put(TYPES["I32"], p + off, value)
        def store8(p, off, value) = Memory.put(TYPES["I8"], p + off, value)

        def gates = @host.gates
        def gates_set(word) = @host.gates = word
        def gates_enter = nil

        def word(x) = Host.signed(Host.bits(x))
        def sword(x) = Host.signed(Host.bits(x))
        def value(x) = Host.signed(Host.bits(x))
        def ptr(x) = Host.bits(x) & MASK
        def u8(x) = x & 0xFF
        def u32(x) = x & 0xFFFF_FFFF
        def i8(x) = narrow(Host.bits(x), 8)
        def i32(x) = narrow(Host.bits(x), 32)

        def add_wrap(a, b) = Host.signed(a + b)
        def sub_wrap(a, b) = Host.signed(a - b)
        def mul_wrap(a, b) = Host.signed(a * b)
        def shl_wrap(a, b) = Host.signed(a << (b & 63))
        def uadd_wrap(a, b) = (a + b) & MASK
        def usub_wrap(a, b) = (a - b) & MASK
        def umul_wrap(a, b) = (a * b) & MASK
        def ushl_wrap(a, b) = (a << (b & 63)) & MASK

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
      # returns.
      SLOT_BYTES = 64 << 20

      attr_reader :kern, :symbols, :sigs
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
        @closures = {}
        @functions = {}
        @sigs = {}
        @gates = 0
        @errno = Memory.zeroed(8)
        @slot_base = Memory.zeroed(SLOT_BYTES)
        @slot_top = @slot_base + SLOT_BYTES
        @kern = kernel_module
        constants.each { |name, value| @kern.const_set(name, value) }
        trees = files.to_h { |file| [file, Prism.parse_file(file).value] }
        load_order(trees).each { |file| load(file) }
        trees.each_value { |tree| frame_slots(tree) }
      end

      # Calls the kernel def `name`.
      def call(name, *args) = @kern.public_send(name, *args)

      # A call of a C function or of the def that answers it.
      def libc(name, params, ret, args)
        return @errno if %w[__error __errno_location].include?(name)
        return @kern.public_send(name, *args) if @kern.method_defined?(name)

        function = @functions[name] ||= Fiddle::Function.new(Fiddle::Handle::DEFAULT[name], params.map(&:fiddle), ret.fiddle)
        foreign(function, params, ret, args)
      end

      # A call through the pointer `at`: a def that `Machine.addr` gave, or
      # C code.
      def call_at(at, params, ret, args)
        if (name = @callables[at])
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
          @callables[closure.to_i] = name
          @closures[name] = closure
        end.to_i
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

      def slot(size)
        @slot_top -= size + ((-size) % 16)
        raise "the slot area is full" if @slot_top < @slot_base

        @slot_top
      end

      # Where the next slot ends; a def that takes slots puts it back.
      attr_accessor :slot_top

      private

      # A fresh `Zr::Kern` with the forms a kernel file declares with.
      def kernel_module
        host = self
        kern = Module.new
        kern.extend(kern)
        TYPES.each { |name, type| kern.const_set(name, type) }
        kern.const_set(:Machine, Intrinsics.new(self))
        kern.const_set(:Libc, Libc.new(self))
        pending = nil
        kern.define_singleton_method(:layout) { |**fields| Layout.new(fields) }
        kern.define_singleton_method(:fn) { |signature| Fn.new(host, *signature.first) }
        kern.define_singleton_method(:sig) { |signature| pending = signature.first }
        kern.define_singleton_method(:inline) { |_name| nil }
        kern.define_singleton_method(:collects) { |_name| nil }
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

      # Each def of the file that takes a slot gives its slots back when it
      # returns.
      def frame_slots(tree)
        names = statements(tree).grep(Prism::DefNode).select { |node| node.slice.include?("Machine.slot(") }.map(&:name)
        return if names.empty?

        host = self
        frames = Module.new
        names.uniq.each do |name|
          frames.define_method(name) do |*args|
            top = host.slot_top
            begin
              super(*args)
            ensure
              host.slot_top = top
            end
          end
        end
        @kern.prepend(frames)
      end

      def foreign(function, params, ret, args)
        values = args.zip(params).map { |arg, type| to_c(arg, type) }
        Fiddle::Pointer.write(errno_location, [Memory.read(@errno, 4).unpack1("l<")].pack("l<"))
        result = function.call(*values)
        Memory.write(@errno, [Fiddle.last_error.to_i].pack("l<"))
        from_c(result, ret)
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
        when "Ptr" then value.to_i & MASK
        when "Bool" then value != 0
        when "Void" then nil
        else value
        end
      end
    end
  end
end
