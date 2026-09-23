# frozen_string_literal: true

require_relative "function"
require_relative "types"
require_relative "../record"

module Ze0
  module IR
    # An interpreter over `IR::Function`: a second answer for every program
    # the kernel dialect can write, owing nothing to the aarch64 backend. A
    # disagreement between this and the compiled binary names a miscompile;
    # the same wrong answer from both names a lowering bug.
    #
    # It models the machine `Backend::Aarch64::Codegen` targets rather than an abstract one.
    # Every value lives in a 64-bit slot and each use reads its own type's
    # width out of it, so a narrowing the backend defers to the next load is
    # deferred here too. Arithmetic on a type below `i64` runs 32 bits wide,
    # as the w-registers do. Where the two disagree the backend is right and
    # this file has the bug.
    class Interp
      MASK = { 8 => 0xFF, 32 => 0xFFFF_FFFF, 64 => (1 << 64) - 1 }.freeze
      BITS = { "i8" => 8, "i32" => 32, "i64" => 64, "f64" => 64 }.freeze
      # The stack every program gets, and the deepest call chain Ruby's
      # own stack will carry for us.
      STACK = 1 << 22
      DEPTH = 4096

      # The interpreter does not model this program.
      class Refused < StandardError; end
      # The program did something no machine would carry out.
      class Trapped < StandardError; end
      # The program called `abort`.
      class Aborted < Trapped; end

      # The program called `exit`.
      class Exited < StandardError
        attr_reader :status

        def initialize(status)
          @status = status
          super("exit(#{status})")
        end
      end

      # A flat byte-addressed store. Addresses are offsets into one string,
      # and the first page is never handed out, so a null dereference traps
      # the way it would on the machine.
      class Memory
        GUARD = 0x1000

        def initialize
          @bytes = ("\0".b * GUARD)
        end

        # The next address at `align`, with `size` bytes of room after it.
        def reserve(size, align = 8)
          at = (@bytes.bytesize + align - 1) & ~(align - 1)
          grow(at + size)
          at
        end

        # `string` in memory, at its own address.
        def place(string, align = 8)
          at = reserve(string.bytesize, align)
          @bytes[at, string.bytesize] = string.b
          at
        end

        def read(addr, width)
          reach(addr, width)
          @bytes.byteslice(addr, width).unpack1(PACK.fetch(width))
        end

        def write(addr, width, value)
          reach(addr, width)
          @bytes[addr, width] = [value].pack(PACK.fetch(width))
        end

        # The `len` bytes at `addr`, for a host call that takes a buffer.
        def slice(addr, len)
          reach(addr, len)
          @bytes.byteslice(addr, len)
        end

        PACK = { 1 => "C", 4 => "L<", 8 => "Q<" }.freeze

        private

        def grow(size)
          @bytes << ("\0".b * (size - @bytes.bytesize)) if size > @bytes.bytesize
        end

        def reach(addr, width)
          return if addr >= GUARD && addr + width <= @bytes.bytesize

          raise Trapped, format("address 0x%x is outside the program's memory", addr)
        end
      end

      # The libSystem calls a kernel-dialect program makes. Every one it
      # can reach is here; anything else is refused by name rather than
      # answered wrongly.
      class Host
        def initialize(memory, out: $stdout, err: $stderr)
          @memory = memory
          @io = { 1 => out, 2 => err }
        end

        def knows?(name) = CALLS.key?(name)

        def call(name, args)
          public_send(CALLS.fetch(name), *args)
        end

        def sys_write(fd, buf, len)
          io = @io[fd] or raise Trapped, "a write to descriptor #{fd}"
          io.write(@memory.slice(buf, len))
          len
        end

        def sys_exit(status)
          raise Exited, status & 0xFF
        end

        def sys_abort
          raise Aborted, "the program called abort"
        end

        # Anonymous pages only, which is all the collector asks for.
        def sys_mmap(_addr, len, _prot, _flags, _fd, _offset)
          @memory.reserve(len, 0x4000)
        end

        CALLS = { "write" => :sys_write, "exit" => :sys_exit, "_exit" => :sys_exit, "abort" => :sys_abort, "mmap" => :sys_mmap }.freeze
      end

      # One call's state: the values it has defined, and the addresses of
      # the stack slots it owns.
      class Frame < Ze0::Record
        FIELDS = %i[values slot_at types].freeze
        attr_accessor :values, :slot_at, :types

        def initialize(values = nil, slot_at = nil, types = nil)
          @values = values
          @slot_at = slot_at
          @types = types
        end

        def to_a = [@values, @slot_at, @types]
      end

      attr_reader :memory

      # `functions` are `IR::Function`s, `data` and `raw` are `Obj::Data`
      # and `Obj::Function`. A `raw` function is machine code rather than
      # IR, so a call to one is refused by name rather than skipped over.
      def initialize(functions, data: [], raw: [], out: $stdout, err: $stderr)
        @functions = functions.to_h { |f| [f.name, f] }
        @raw = raw.map(&:name)
        @memory = Memory.new
        @types = {}
        @data_at = {}
        @code_at = {}
        @symbol_at = {}
        @depth = 0
        place_data(data)
        place_code(functions.map(&:name) + @raw)
        # Only now does every symbol have a place, which is what a
        # relocation in data needs.
        relocate(data)
        @floor = @memory.reserve(STACK, 16)
        @sp = @floor + STACK
        @host = Host.new(@memory, out: out, err: err)
      end

      # Run `main(argc, argv)` and answer the exit status, as a shell sees
      # it: what `exit` was given, or what `main` returned.
      def run(argv = [])
        argc, vector = place_argv(argv)
        answer("main", [argc, vector]) & 0xFF
      rescue Exited => e
        e.status
      end

      # The raw value `name` answers for `args`. Numbers in and out are the
      # 64-bit words the machine would pass.
      def answer(name, args = [])
        f = @functions[name] or raise Refused, "no function named #{name}"
        invoke(f, args)
      end

      private

      # --- the image ----------------------------------------------------

      def place_data(data)
        data.each do |d|
          bytes = d.section == :bss ? "\0".b * d.bytes : d.bytes
          @data_at[d.name] = @memory.place(bytes, [d.align, 1].max)
        end
      end

      def relocate(data)
        data.each { |d| d.relocs.each { |r| patch(@data_at.fetch(d.name) + r.offset, r) } }
      end

      def patch(at, reloc)
        raise Refused, "a #{reloc.kind} relocation in data" unless reloc.kind == :abs64

        @memory.write(at, 8, (address_of(reloc.symbol) + reloc.addend.to_i) & MASK[64])
      end

      # Every function gets an address of its own, imports included, so
      # `func_addr` and a call through a pointer both have one to name.
      def place_code(names)
        names.each do |name|
          at = @memory.reserve(8, 8)
          @code_at[name] = at
          @symbol_at[at] = name
        end
      end

      def address_of(symbol)
        @data_at[symbol] || @code_at[symbol] ||
          raise(Refused, "nothing in this unit defines #{symbol}")
      end

      # `argv` as a NUL-terminated vector of NUL-terminated strings.
      def place_argv(argv)
        pointers = argv.map { |arg| @memory.place("#{arg}\0".b, 1) }
        vector = @memory.reserve(8 * (pointers.size + 1), 8)
        pointers.each_with_index { |at, n| @memory.write(vector + 8 * n, 8, at) }
        [argv.size, vector]
      end

      # --- calls --------------------------------------------------------

      def invoke(f, args)
        raise Trapped, "the call depth reached #{DEPTH}" if @depth >= DEPTH

        t = types_of(f)
        sp = @sp
        frame = enter(f, t, args)
        @depth += 1
        begin
          walk(f, frame, t)
        ensure
          @depth -= 1
          @sp = sp
        end
      end

      def types_of(f)
        @types[f.name] ||= Types.new(f).tap(&:all)
      end

      # The frame: its stack slots in memory, and its parameters bound to
      # the arguments, each narrowed to the parameter's own type.
      def enter(f, t, args)
        entry = f.entry_block
        raise Refused, "#{f.name}: more than eight parameters" if entry.params.size > REGISTER_ARGS

        raise Refused, "#{f.name}: #{args.size} arguments for #{entry.params.size} parameters" if args.size != entry.params.size

        off = 0
        slot_at = f.slots.map do |s|
          off = round_up(off, [s.align, 8].max)
          at = off
          off += s.bytes
          at
        end
        # The saved frame pointer and link register are 16 bytes every
        # frame pays, so a recursion with no slots still reaches the floor.
        @sp -= round_up(off, 16) + 16
        raise Trapped, "the stack is exhausted" if @sp < @floor

        frame = Frame.new({}, slot_at.map { |at| @sp + 16 + at }, t)
        entry.params.each_with_index { |(v, type), n| frame.values[v] = narrow(args[n], type) }
        frame
      end

      def walk(f, frame, t)
        block = f.entry_block
        while block
          block, answer, done = run_block(block, frame, t)
          return answer if done
        end
        raise Refused, "#{f.name}: a block with no terminator"
      end

      # A block to its successor, or to the value the function answers.
      def run_block(block, frame, t)
        block.insts.each do |i|
          case i.op
          when :return
            return [nil, i.args.empty? ? 0 : read(frame, i.args[0]), true]
          when :jump
            return [jump(frame, t, i.targets[0]), nil, false]
          when :brif
            raise Refused, "a brif carrying block arguments" unless i.targets.all? { |(_, a)| a.empty? }

            yes, no = i.targets
            return [jump(frame, t, read(frame, i.args[0]).zero? ? no : yes), nil, false]
          else step(frame, t, i)
          end
        end
        raise Refused, "#{block.name} has no terminator"
      end

      # A block's arguments to its parameters, every source read before any
      # parameter is written: the copy is parallel, as the backend's is.
      def jump(frame, t, target)
        name, args = target
        block = t.block_named(name)
        values = args.map { |v| read(frame, v) }
        block.params.each_with_index { |(v, _), n| frame.values[v] = values[n] }
        block
      end

      # --- values -------------------------------------------------------

      # A value as its own type reads it out of the 64-bit slot.
      def read(frame, v)
        raw = frame.values.fetch(v) { raise Refused, "#{v} is used before it is defined" }
        raw & MASK.fetch(BITS.fetch(frame.types.of(v)))
      end

      def assign(frame, v, raw)
        frame.values[v] = raw & MASK[64]
      end

      def narrow(raw, type) = raw & MASK.fetch(BITS.fetch(type))

      # The signed reading of `raw`, which holds `bits` of a value.
      def signed(raw, bits)
        top = 1 << (bits - 1)
        raw >= top ? raw - (top << 1) : raw
      end

      def round_up(n, a) = (n + a - 1) & ~(a - 1)

      # An operation on a type below `i64` runs in a w-register, so it is
      # 32 bits wide and its result has zeros above.
      def width_of(frame, v) = BITS.fetch(frame.types.of(v)) == 64 ? 64 : 32

      def to_f64(raw) = [raw].pack("Q<").unpack1("E")
      def to_bits(float) = [float].pack("E").unpack1("Q<")

      # --- instructions -------------------------------------------------

      def step(frame, t, i)
        case i.op
        when :iconst then assign(frame, i.results[0], i.args[0])
        when :load then step_load(frame, i)
        when :store then step_store(frame, i)
        when :stack_addr then assign(frame, i.results[0], frame.slot_at.fetch(slot_index(i.args[0])))
        when :symbol_value then assign(frame, i.results[0], address_of(t.global_named(i.args[0]).symbol))
        when :func_addr then assign(frame, i.results[0], address_of(t.callee_named(i.args[0]).symbol))
        when :call then step_call(frame, t, i)
        when :call_indirect then step_call_indirect(frame, t, i)
        when :icmp then assign(frame, i.results[0], compare(frame, i) ? 1 : 0)
        when :select
          taken = read(frame, i.args[0]).zero? ? i.args[2] : i.args[1]
          assign(frame, i.results[0], read(frame, taken) & MASK[width_of(frame, i.args[1])])
        when :ireduce, :uextend, :bitcast then assign(frame, i.results[0], read(frame, i.args[0]))
        when :sextend
          bits = BITS.fetch(frame.types.of(i.args[0]))
          assign(frame, i.results[0], signed(read(frame, i.args[0]), bits == 8 ? 8 : 32))
        when *Inst::BINOPS then assign(frame, i.results[0], binop(frame, i))
        when *Inst::BITOPS then assign(frame, i.results[0], bitop(frame, i))
        when :sadd_overflow, :ssub_overflow, :smul_overflow then step_overflow(frame, i)
        when *Inst::FBINOPS, *Inst::FUNOPS, :fcvt_from_sint, :fcvt_to_sint_sat
          assign(frame, i.results[0], float_op(frame, i))
        when :fcmp then assign(frame, i.results[0], float_compare(frame, i) ? 1 : 0)
        # The register the gate word lives in is the word itself here,
        # which every writer stores before it sets the register.
        when :gates then assign(frame, i.results[0], @memory.read(address_of(GATES), 8))
        when :gates_set, :gates_enter then nil
        else raise Refused, "no interpretation for #{i.op}"
        end
      end

      GATES = "zr_static_gates"

      def slot_index(name) = Integer(name.delete_prefix("ss"))

      def step_load(frame, i)
        width = Types::WIDTH.fetch(i.type) { raise Refused, "load.#{i.type}" }
        assign(frame, i.results[0], @memory.read(read(frame, i.args[0]) + i.offset, width))
      end

      def step_store(frame, i)
        width = Types::WIDTH.fetch(frame.types.of(i.args[0]))
        @memory.write(read(frame, i.args[1]) + i.offset, width, read(frame, i.args[0]) & MASK[width * 8])
      end

      def compare(frame, i)
        bits = width_of(frame, i.args[0])
        a = read(frame, i.args[0])
        b = read(frame, i.args[1])
        a, b = signed(a, bits), signed(b, bits) if i.cond.start_with?("s")
        case i.cond
        when "eq" then a == b
        when "ne" then a != b
        when "slt", "ult" then a < b
        when "sle", "ule" then a <= b
        when "sgt", "ugt" then a > b
        when "sge", "uge" then a >= b
        else raise Refused, "no such condition: #{i.cond}"
        end
      end

      # The two-operand integer instructions. Division by zero answers zero,
      # as `udiv` and `sdiv` do, and a shift takes its amount modulo the
      # width, as the register forms do.
      def binop(frame, i)
        bits = width_of(frame, i.args[0])
        mask = MASK[bits]
        a = read(frame, i.args[0])
        b = read(frame, i.args[1])
        sa = signed(a, bits)
        sb = signed(b, bits)
        case i.op
        when :iadd then a + b
        when :isub then a - b
        when :imul then a * b
        when :band then a & b
        when :bor then a | b
        when :bxor then a ^ b
        when :udiv then b.zero? ? 0 : a / b
        when :sdiv then b.zero? ? 0 : quotient(sa, sb)
        when :urem then b.zero? ? a : a - (a / b) * b
        when :srem then b.zero? ? a : sa - quotient(sa, sb) * sb
        when :ishl then a << (b % bits)
        when :ushr then a >> (b % bits)
        when :sshr then sa >> (b % bits)
        end & mask
      end

      # Division truncating toward zero, which is what arm64 does and what
      # Ruby's `/` (which floors) does not.
      def quotient(a, b) = (a < 0) == (b < 0) ? a.abs / b.abs : -(a.abs / b.abs)

      def step_overflow(frame, i)
        bits = width_of(frame, i.args[0])
        raise Refused, "smul_overflow on #{frame.types.of(i.args[0])}" if i.op == :smul_overflow && bits != 64

        a = signed(read(frame, i.args[0]), bits)
        b = signed(read(frame, i.args[1]), bits)
        exact = case i.op
                when :sadd_overflow then a + b
                when :ssub_overflow then a - b
                else a * b
                end
        top = 1 << (bits - 1)
        assign(frame, i.results[0], exact & MASK[bits])
        assign(frame, i.results[1], exact < -top || exact >= top ? 1 : 0)
      end

      # The bit tricks, as wide as the operand: a count of zero's zeros
      # is the width.
      def bitop(frame, i)
        bits = width_of(frame, i.args[0])
        a = read(frame, i.args[0]) & MASK[bits]
        case i.op
        when :ctz then a.zero? ? bits : (a & -a).bit_length - 1
        when :clz then bits - a.bit_length
        when :popcnt then a.to_s(2).count("1")
        when :bswap then [a].pack(bits == 64 ? "Q>" : "L>").unpack1(bits == 64 ? "Q<" : "L<")
        end
      end

      # `fcvt_to_sint_sat` saturates and answers zero for NaN, as `fcvtzs`
      # does; every other float instruction is Ruby's own on the same bits.
      def float_op(frame, i)
        return to_bits(signed(read(frame, i.args[0]), width_of(frame, i.args[0])).to_f) if i.op == :fcvt_from_sint

        a = to_f64(read(frame, i.args[0]))
        return saturate(a) & MASK[64] if i.op == :fcvt_to_sint_sat

        case i.op
        when :fadd, :fsub, :fmul, :fdiv
          b = to_f64(read(frame, i.args[1]))
          to_bits(a.public_send({ fadd: :+, fsub: :-, fmul: :*, fdiv: :/ }.fetch(i.op), b))
        when :fneg then to_bits(-a)
        when :fabs then to_bits(a.abs)
        when :sqrt then to_bits(a.negative? ? Float::NAN : Math.sqrt(a))
        when :floor then to_bits(a.finite? ? a.floor.to_f : a)
        when :ceil then to_bits(a.finite? ? a.ceil.to_f : a)
        when :trunc then to_bits(a.finite? ? a.truncate.to_f : a)
        when :nearest then to_bits(a.finite? ? a.round(half: :even).to_f : a)
        end
      end

      def saturate(a)
        return 0 if a.nan?

        a.clamp(-(2**63).to_f, (2**63 - 1).to_f).truncate.clamp(-(2**63), 2**63 - 1)
      end

      # Every condition but `ne` reads an unordered pair as false, which is
      # what Ruby's own comparisons answer for NaN.
      def float_compare(frame, i)
        a = to_f64(read(frame, i.args[0]))
        b = to_f64(read(frame, i.args[1]))
        case i.cond
        when "eq" then a == b
        when "ne" then a != b
        when "lt" then a < b
        when "le" then a <= b
        when "gt" then a > b
        when "ge" then a >= b
        else raise Refused, "no such float condition: #{i.cond}"
        end
      end

      # --- calls --------------------------------------------------------

      def step_call(frame, t, i)
        callee = t.callee_named(i.callee) or raise Refused, "no callee #{i.callee}"
        apply(frame, i, callee.symbol, t.sig_named(callee.sig))
      end

      def step_call_indirect(frame, t, i)
        sig = t.sig_named(i.callee)
        at = read(frame, i.args[0])
        symbol = @symbol_at[at] or raise Trapped, format("a call through 0x%x, which is not a function", at)
        apply(frame, i, symbol, sig, i.args.drop(1))
      end

      def apply(frame, i, symbol, sig, args = i.args)
        raise Refused, "a call with more than eight arguments" if args.size > REGISTER_ARGS

        raw = dispatch(symbol, args.map { |v| read(frame, v) })
        return if i.results.empty?

        # A result narrower than a word comes back with zeros above it.
        assign(frame, i.results[0], BITS.fetch(sig.ret) == 64 ? raw.to_i : raw.to_i & MASK[32])
      end

      def dispatch(symbol, args)
        f = @functions[symbol]
        return invoke(f, args) if f
        return @host.call(symbol, args) if @host.knows?(symbol)
        raise Refused, "#{symbol} is machine code, not IR" if @raw.include?(symbol)

        raise Refused, "nothing in this unit or the host defines #{symbol}"
      end
    end
  end
end
