# frozen_string_literal: true

require_relative "../../../bytes"
require_relative "../../../config"
require_relative "../../../ir/types"
require_relative "../locals"

module Zr
  module Backend
    module Wasm
      class Codegen
        # One function's body.
        class Body
          # @rbs @m: Codegen
          # @rbs @f: IR::Function
          # @rbs @local: Hash[String, Integer]
          # @rbs @types: IR::Types
          # @rbs @type: Hash[String, String?]
          # @rbs @code: String
          # @rbs @const: Hash[String, IR::Inst]
          # @rbs @locals: Array[Integer]
          # @rbs @bb: Integer
          # @rbs @fp: Integer
          # @rbs @slot_at: Array[Integer]
          # @rbs @frame: Integer
          # @rbs @width: Integer
          # @rbs @groups: Integer
          # @rbs @gk: Integer
          # @rbs @group: Range[Integer]
          # @rbs @outer: Integer
          # @rbs @span: Integer
          # @rbs @row: Integer
          # @rbs @bias: Integer

          # A function with more blocks than this dispatches in two steps,
          # in groups of this size. For the code that zr emits, a group of
          # 256 compiles fastest at every size tested: 8,000 blocks take
          # 20.0 s in groups of 128, 9.9 s in 256, and 11.3 s in 512. The
          # square root of the block count is much slower.
          LADDER = 256

          #: (Codegen mod, IR::Function f) -> void
          def initialize(mod, f)
            @m = mod
            @f = f
            @local = {}
            @types = IR::Types.new(f)
            @type = {}
            @code = +"".b
          end

          #: () -> String
          def emit
            assign
            prologue
            dispatch
            @code << "\x0B".b
            locals = @locals.chunk_while { |a, b| a == b }.map { |run| Bytes.leb(run.size) + run.first.chr }
            @m.vec_bytes(@m.vec(locals) + @code)
          end

          private

          # Parameters first, then the shared locals for all other values,
          # then the block index and the frame base. A constant has no local:
          # it is written where it is read (`CONSTANTS`).
          #: () -> void
          def assign
            n = 0
            @const = {}
            # The IR gives the type of every value (`IR::Types`), so this
            # backend and the other backends read each value as the same type.
            @type = @types.all
            @f.blocks.first.params.each do |v, _|
              @local[v] = n
              n += 1
            end
            values = [] #: Array[[String, Integer]]
            @f.blocks.each_with_index do |b, bi|
              b.params.each { |v, t| values << [v, Codegen::TYPE.fetch(t)] unless bi.zero? }
              b.insts.each do |i|
                i.results.each do |v|
                  if CONSTANTS.include?(i.op)
                    @const[v] = i
                  else
                    values << [v, Codegen::TYPE.fetch(@type[v])]
                  end
                end
              end
            end
            shared, @locals = Locals.of(@f, values, n)
            @local.merge!(shared)
            @bb = n + @locals.size
            @locals << 0x7F
            @fp = n + @locals.size
            @locals << 0x7F
            off = 0
            @slot_at = @f.slots.map do |s|
              off = Bytes.align(off, [s.align, 8].max)
              at = off
              off += s.bytes
              at
            end
            @frame = Bytes.align(off, 16)
          end

          # Every name in a function's instructions is defined in it.
          #: (String? fn) -> IR::Callee
          def callee(fn) = @types.callee_named(fn) #: IR::Callee
          #: (String? sig) -> IR::Sig
          def sig_named(sig) = @types.sig_named(sig)
          #: (String gv) -> IR::Global
          def global(gv) = @types.global_named(gv) #: IR::Global
          #: (String name) -> IR::Block
          def block_named(name) = @types.block_named(name)

          #: (String v) -> bool
          def wide?(v)
            @type.fetch(v) == "i64"
          end

          # A division, with the IR result (lib/zr/ir/inst.rb). For a zero
          # divisor, `udiv`/`sdiv` return 0 and `urem`/`srem` return the
          # dividend. The most negative number divided by -1 wraps. wasm's
          # `div` traps on both, so each has a guard. wasm's `rem_s` of that
          # pair returns 0, as the IR does, so it needs no guard.
          #: (IR::Inst i) -> void
          def divide(i)
            a, b = i.args
            wide = wide?(a)
            type = wide ? "\x7E".b : "\x7F".b
            zero = wide ? "\x42\x00".b : "\x41\x00".b
            table = ops(a)
            get(b)
            @code << (wide ? "\x50".b : "\x45".b) << "\x04".b << type
            if %i[urem srem].include?(i.op)
              get(a)
            else
              @code << zero
            end
            @code << "\x05".b
            if i.op == :sdiv
              get(b)
              @code << (wide ? "\x42\x7F".b : "\x41\x7F".b) << table.fetch(:eq).chr << "\x04".b << type << zero
              get(a)
              @code << table.fetch(:sub).chr << "\x05".b
            end
            get(a)
            get(b)
            @code << table.fetch(DIVIDE_OPS[i.op]).chr
            @code << "\x0B".b if i.op == :sdiv
            @code << "\x0B".b
            set(i.results[0])
          end

          #: (String v) -> Hash[Symbol, Integer]
          def ops(v)
            Codegen::OP.fetch(wide?(v) ? "i64" : "i32")
          end

          #: (String v) -> void
          def get(v)
            i = @const[v]
            return constant(i) if i

            @code << "\x20".b << Bytes.leb(@local.fetch(v))
          end

          # The instructions whose value is a constant or comes from the frame
          # base only. They are written where they are used, so they need no
          # local. Thus the constants and slot addresses in the entry block are
          # not live across all later blocks. That liveness is most of the
          # cost of shared locals.
          CONSTANTS = %i[iconst symbol_value func_addr stack_addr].freeze #: Array[Symbol]

          # The `Codegen::OP` key of each division and remainder opcode, of
          # each integer binary opcode, and the wasm opcode byte of each
          # float comparison, float binary and float unary opcode.
          DIVIDE_OPS = { udiv: :div_u, sdiv: :div_s, urem: :rem_u, srem: :rem_s }.freeze #: Hash[Symbol, Symbol]
          BINOP_KEYS = { iadd: :add, isub: :sub, imul: :mul, band: :and, bor: :or, bxor: :xor,
                         ishl: :shl, ushr: :shr_u, sshr: :shr_s }.freeze #: Hash[Symbol, Symbol]
          FCMP_OPCODES = { "eq" => 0x61, "ne" => 0x62, "lt" => 0x63, "gt" => 0x64, "le" => 0x65, "ge" => 0x66 }.freeze #: Hash[String, Integer]
          FBINOP_OPCODES = { fadd: 0xA0, fsub: 0xA1, fmul: 0xA2, fdiv: 0xA3 }.freeze #: Hash[Symbol, Integer]
          FUNOP_OPCODES = { fabs: 0x99, fneg: 0x9A, ceil: 0x9B, floor: 0x9C, trunc: 0x9D, nearest: 0x9E, sqrt: 0x9F }.freeze #: Hash[Symbol, Integer]

          # The load opcode and its alignment of each type.
          LOAD_OPCODES = { "i64" => "\x29\x03".b, "i32" => "\x28\x02".b, "i8" => "\x2D\x00".b, "f64" => "\x2B\x03".b }.freeze #: Hash[String, String]

          # The opcodes of `emit_bswap` (const, and, or, shl, shr, rotl) and
          # its mask and shift steps, for a wide and for a narrow type.
          BSWAP_WIDE = ["\x42", "\x83", "\x84", "\x86", "\x88", "\x89"].freeze #: [String, String, String, String, String, String]
          BSWAP_NARROW = ["\x41", "\x71", "\x72", "\x74", "\x76", "\x77"].freeze #: [String, String, String, String, String, String]
          BSWAP_WIDE_STEPS = [[0x00FF00FF00FF00FF, 8], [0x0000FFFF0000FFFF, 16]].freeze #: Array[[Integer, Integer]]
          BSWAP_NARROW_STEPS = [[0x00FF00FF, 8]].freeze #: Array[[Integer, Integer]]

          #: (IR::Inst i) -> void
          def constant(i)
            case i.op
            when :iconst
              # A constant written unsigned wraps to its signed bits.
              n = i.args[0]
              n -= 1 << 64 if i.type == "i64" && n >= 1 << 63
              n -= 1 << 32 if i.type != "i64" && n >= 1 << 31
              @code << (i.type == "i64" ? "\x42".b : "\x41".b) << Bytes.sleb(n)
            when :symbol_value
              @code << "\x42".b << Bytes.sleb(@m.data_address(global(i.args[0]).symbol))
            when :func_addr
              @code << "\x42".b << Bytes.sleb(@m.table_index(callee(i.args[0]).symbol))
            when :stack_addr
              @code << "\x20".b << Bytes.leb(@fp) << @m.i32c(@slot_at[Integer(i.args[0].delete_prefix("ss"))]) << "\x6A".b << "\xAD".b
            end
          end

          #: (String v) -> void
          def set(v)
            @code << "\x21".b << Bytes.leb(@local.fetch(v))
          end

          # The frame: global 0 is the stack pointer. It is saved in the
          # frame base local and incremented past the slots.
          #: () -> void
          def prologue
            @code << "\x23\x00".b << "\x22".b << Bytes.leb(@fp)
            @code << @m.i32c(@frame) << "\x6A".b << "\x24\x00".b
            @code << @m.i32c(0) << "\x21".b << Bytes.leb(@bb)
          end

          #: () -> void
          def epilogue
            @code << "\x20".b << Bytes.leb(@fp) << "\x24\x00".b
          end

          # loop { block ... block { br_table } body0 end body1 end ... }
          # Each block starts where a wasm `block` ends, and a branch out of
          # that `block` reaches it. N blocks nest N deep, and the wasm compile
          # time grows with the square of that depth: 1,000 blocks take 0.2 s
          # and 14,000 take 78 s. The core library has one function with 14,793
          # blocks (the table that UnicodeNormalize builds). Thus a function with
          # more than `LADDER` blocks dispatches in two steps: the index selects
          # a group, and the group selects the block. The deepest nesting is then
          # about two times the square root of the block count.
          #: () -> void
          def dispatch
            n = @f.blocks.size
            @code << "\x03\x40".b
            if n <= LADDER
              ladder(@f.blocks, 0, 0)
            else
              @width = Config.current.wasm_width
              groups = @f.blocks.each_slice(@width).to_a
              @groups = groups.size
              groups.size.times { @code << "\x02\x40".b }
              @code << "\x20".b << Bytes.leb(@bb) << @m.i32c(@width) << "\x6E".b
              table(groups.size)
              groups.each_with_index do |group, k|
                @code << "\x0B".b
                @code << "\x03\x40".b
                @gk = k
                ladder(group, k * @width, groups.size - k)
                @code << "\x0B".b << "\x00".b
              end
            end
            @code << "\x0B".b
            # Every block ends in a branch or a return, so the end of the
            # loop is unreachable. `unreachable` tells this to the validator.
            @code << "\x00".b
          end

          # One group of blocks with its own `br_table`. `first` is the index
          # of its first block. `outer` is the number of constructs between
          # the group's loop and the function's loop. It is 0 when the group
          # is the whole function.
          #: (Array[IR::Block] blocks, Integer first, Integer outer) -> void
          def ladder(blocks, first, outer)
            m = blocks.size
            m.times { @code << "\x02\x40".b }
            @code << "\x20".b << Bytes.leb(@bb)
            @code << @m.i32c(first) << "\x6B".b unless first.zero?
            table(m)
            @group = first..(first + m - 1)
            @outer = outer
            @span = m
            blocks.each_with_index do |b, j|
              @code << "\x0B".b
              @row = j
              @bias = 0
              b.insts.each { |inst| emit_inst(inst) }
            end
          end

          # `br_table` over `count` labels, with the first as the default.
          # An index past the end cannot occur, because every branch goes to
          # a block of this function.
          #: (Integer count) -> void
          def table(count)
            @code << "\x0E".b << Bytes.leb(count)
            count.times { |i| @code << Bytes.leb(i) }
            @code << Bytes.leb(0)
          end

          # A branch to `name`: set the block index, then branch to the
          # `br_table` that reads it. That is the group's loop when the block
          # is in this group, and the function's loop when it is not.
          #
          # A branch out of the `block` that ends where a later block starts
          # reaches that block directly with no index. But it is 8 to 20 times
          # slower to compile: 2,000 blocks take 0.24 s with the `br_table` and
          # 4.93 s without it. Thus every branch goes through a `br_table`.
          #: (String name) -> void
          def go(name)
            at = @f.blocks.index { |b| b.name == name } #: Integer
            @code << @m.i32c(at) << "\x21".b << Bytes.leb(@bb)
            @code << "\x0C".b << Bytes.leb((@span - 1 - @row + @bias) + reach(at))
          end

          # The number of constructs past this group's loop that a branch to the
          # block at `at` must leave. It is 0 when the block is in this group.
          # A later group is a `block` that contains this group, so a branch out
          # of it reaches that group's `br_table`. Thus the function's loop does
          # not get a predecessor for each branch that leaves a group. Only a
          # branch to an earlier group goes to the function's loop.
          #: (Integer at) -> Integer
          def reach(at)
            return 0 if @group.cover?(at)

            ahead = (at / @width) - @gk
            ahead.positive? ? ahead : @outer
          end

          WIDE_BITOPS = { clz: "\x79".b, ctz: "\x7A".b, popcnt: "\x7B".b }.freeze #: Hash[Symbol, String]
          NARROW_BITOPS = { clz: "\x67".b, ctz: "\x68".b, popcnt: "\x69".b }.freeze #: Hash[Symbol, String]

          # wasm has no byte swap. Swap the bytes in pairs, then the pairs,
          # then the halves: `(x & m) << k | (x >> k) & m` for each mask, and a
          # rotate for the halves. Each step reads the result's local.
          #: (IR::Inst i) -> void
          def emit_bswap(i)
            v = i.results[0]
            wide = wide?(i.args[0])
            const, and_, or_, shl, shr, rotl = wide ? BSWAP_WIDE : BSWAP_NARROW
            steps = wide ? BSWAP_WIDE_STEPS : BSWAP_NARROW_STEPS
            from = i.args[0]
            steps.each do |mask, k|
              get(from)
              @code << const.b << Bytes.sleb(mask) << and_.b << const.b << Bytes.sleb(k) << shl.b
              get(from)
              @code << const.b << Bytes.sleb(k) << shr.b << const.b << Bytes.sleb(mask) << and_.b << or_.b
              set(v)
              from = v
            end
            get(from)
            @code << const.b << Bytes.sleb(wide ? 32 : 16) << rotl.b
            set(v)
          end

          #: (IR::Inst i) -> void
          def emit_load(i)
            get(i.args[0])
            @code << "\xA7".b
            @code << LOAD_OPCODES.fetch(i.type) << Bytes.leb(i.offset)
            set(i.results[0])
          end

          #: (IR::Inst i) -> void
          def emit_store(i)
            get(i.args[1])
            @code << "\xA7".b
            get(i.args[0])
            @code << { "i64" => "\x37\x03".b, "i32" => "\x36\x02".b, "i8" => "\x3A\x00".b, "f64" => "\x39\x03".b }.fetch(@type[i.args[0]]) << Bytes.leb(i.offset)
          end

          #: (IR::Inst i) -> void
          def emit_call_indirect(i)
            ptr, *args = i.args
            args.each { |a| get(a) }
            get(ptr)
            @code << "\xA7".b
            params, results = @m.sig_type(sig_named(i.callee))
            @code << "\x11".b << Bytes.leb(@m.type_index([params, results])) << "\x00".b
            if i.results.empty?
              # Drop a return value that the instruction does not use.
              @code << "\x1A".b unless results.empty?
            else
              set(i.results[0])
            end
          end

          #: (IR::Inst i) -> void
          def emit_call(i)
            # A libc call's text signature can give i64 where the shim
            # takes i32. The callee sets the width.
            name = callee(i.callee).symbol
            params, results = @m.function_type(name) || @m.sig_type(sig_named(callee(i.callee).sig))
            i.args.zip(params).each do |a, want|
              get(a)
              @code << "\xA7".b if wide?(a) && want == 0x7F
              @code << "\xAD".b if !wide?(a) && want == 0x7E && @type[a] != "f64"
            end
            @code << "\x10".b << Bytes.leb(@m.function_index(name))
            if i.results.empty?
              # Drop a return value that the text signature does not give.
              @code << "\x1A".b unless results.empty?
            else
              @code << "\xA7".b if results.first == 0x7E && !wide?(i.results[0])
              @code << "\xAD".b if results.first == 0x7F && wide?(i.results[0])
              set(i.results[0])
            end
          end

          #: (IR::Inst i) -> void
          def emit_icmp(i)
            get(i.args[0])
            get(i.args[1])
            @code << ops(i.args[0]).fetch(Codegen::COND.fetch(i.cond)).chr
            set(i.results[0])
          end

          #: (IR::Inst i) -> void
          def emit_fcmp(i)
            get(i.args[0])
            get(i.args[1])
            @code << FCMP_OPCODES.fetch(i.cond).chr
            set(i.results[0])
          end

          #: (IR::Inst i) -> void
          def emit_fbinop(i)
            get(i.args[0])
            get(i.args[1])
            @code << FBINOP_OPCODES.fetch(i.op).chr
            set(i.results[0])
          end

          #: (IR::Inst i) -> void
          def emit_binop(i)
            get(i.args[0])
            get(i.args[1])
            @code << ops(i.args[0]).fetch(BINOP_KEYS[i.op]).chr
            set(i.results[0])
          end

          #: (IR::Inst i) -> void
          def emit_select(i)
            get(i.args[1])
            get(i.args[2])
            get(i.args[0])
            # A wide condition is tested, not wrapped: any nonzero
            # value selects the first operand.
            @code << "\x50".b << "\x45".b if wide?(i.args[0])
            @code << "\x1B".b
            set(i.results[0])
          end

          #: (IR::Inst i) -> void
          def emit_overflow(i)
            # r = a op b; overflow when the sign of r differs from a and (for
            # add) b, or from a and not b (for sub).
            get(i.args[0])
            get(i.args[1])
            @code << ops(i.args[0]).fetch(i.op == :sadd_overflow ? :add : :sub).chr
            set(i.results[0])
            get(i.args[0])
            get(i.results[0])
            @code << ops(i.args[0]).fetch(:xor).chr
            get(i.args[1])
            get(i.results[0])
            @code << ops(i.args[0]).fetch(:xor).chr
            if i.op == :ssub_overflow
              @code << (wide?(i.args[0]) ? "\x42\x7F".b : "\x41\x7F".b) << ops(i.args[0]).fetch(:xor).chr
            end
            @code << ops(i.args[0]).fetch(:and).chr
            @code << (wide?(i.args[0]) ? "\x42\x00".b : "\x41\x00".b) << ops(i.args[0]).fetch(:lt_s).chr
            set(i.results[1])
          end

          #: (IR::Inst i) -> void
          def emit_smul_overflow(i)
            raise Refused, "smul_overflow on i32" unless wide?(i.args[0])

            get(i.args[0])
            get(i.args[1])
            @code << "\x7E".b
            set(i.results[0])
            # overflow when a != 0 and r / a != b, or a == -1 and b == MIN
            get(i.args[0])
            @code << "\x50".b
            @code << "\x04\x7F".b
            @code << "\x41\x00".b
            @code << "\x05".b
            get(i.args[0])
            @code << "\x42\x7F".b << "\x51".b
            @code << "\x04\x7F".b
            get(i.args[1])
            @code << "\x42".b << Bytes.sleb(-(1 << 63)) << "\x51".b
            @code << "\x05".b
            get(i.results[0])
            get(i.args[0])
            @code << "\x7F".b
            get(i.args[1])
            @code << "\x52".b
            @code << "\x0B\x0B".b
            set(i.results[1])
          end

          #: (IR::Inst i) -> void
          def emit_brif(i)
            get(i.args[0])
            @code << (wide?(i.args[0]) ? "\x50".b : "\x45".b)
            # The value on the stack is 1 when the condition is false, and
            # the `if` adds one label between here and the loop.
            @code << "\x04\x40".b
            @bias += 1
            go(i.targets[1][0])
            @code << "\x05".b
            go(i.targets[0][0])
            @bias -= 1
            @code << "\x0B".b
          end

          # A jump table as a compare for each key: wasm's own `br_table`
          # indexes the dispatch's labels, not the blocks of the IR.
          #: (IR::Inst i) -> void
          def emit_switch(i)
            v, *keys = i.args
            names = i.targets.map(&:first)
            default = names.fetch(0)
            wide = wide?(v)
            keys.each_with_index do |k, n|
              to = names.fetch(n + 1)
              get(v)
              k -= 1 << 64 if wide && k >= 1 << 63
              k -= 1 << 32 if !wide && k >= 1 << 31
              @code << (wide ? "\x42".b : "\x41".b) << Bytes.sleb(k) << ops(v).fetch(:eq).chr
              @code << "\x04\x40".b
              @bias += 1
              go(to)
              @bias -= 1
              @code << "\x0B".b
            end
            go(default)
          end

          #: (IR::Inst i) -> void
          def emit_jump(i)
            name, args = i.targets[0]
            params = block_named(name).params
            args.each { |a| get(a) }
            args.each_index.reverse_each { |k| set(params[k][0]) }
            go(name)
          end

          #: (IR::Inst i) -> void
          def emit_inst(i)
            case i.op
            # CONSTANTS, written out. test/unit/case_lists_test.rb checks it.
            when :iconst, :symbol_value, :func_addr, :stack_addr
              # Written where it is read.
              nil
            when :load then emit_load(i)
            when :store then emit_store(i)
            when :ctz, :clz, :popcnt
              get(i.args[0])
              @code << (wide?(i.args[0]) ? WIDE_BITOPS : NARROW_BITOPS).fetch(i.op)
              set(i.results[0])
            when :bswap then emit_bswap(i)
            # The gate word is global 2. Each use reads it again, because a
            # call can set it before a later read of the value.
            when :gates
              @code << "\x23\x02".b
              set(i.results[0])
            when :gates_set, :gates_enter
              get(i.args[0])
              @code << "\x24\x02".b
            when :call_indirect then emit_call_indirect(i)
            when :call then emit_call(i)
            when :icmp then emit_icmp(i)
            when :fcmp then emit_fcmp(i)
            # IR::Inst::FBINOPS, written out.
            when :fadd, :fsub, :fmul, :fdiv then emit_fbinop(i)
            # IR::Inst::FUNOPS, written out.
            when :fneg, :fabs, :sqrt, :floor, :ceil, :trunc, :nearest
              get(i.args[0])
              @code << FUNOP_OPCODES.fetch(i.op).chr
              set(i.results[0])
            when :fcvt_from_sint
              get(i.args[0])
              @code << "\xB9".b
              set(i.results[0])
            when :fcvt_to_sint_sat
              get(i.args[0])
              @code << "\xFC\x06".b
              set(i.results[0])
            when :bitcast
              get(i.args[0])
              @code << (i.type == "f64" ? "\xBF".b : "\xBD".b)
              set(i.results[0])
            when :udiv, :sdiv, :urem, :srem
              divide(i)
            when :iadd, :isub, :imul, :band, :bor, :bxor, :ishl, :ushr, :sshr then emit_binop(i)
            when :select then emit_select(i)
            when :ireduce
              get(i.args[0])
              @code << "\xA7".b if wide?(i.args[0])
              set(i.results[0])
            when :uextend
              get(i.args[0])
              @code << "\xAD".b if i.type == "i64"
              set(i.results[0])
            when :sextend
              get(i.args[0])
              @code << "\xAC".b if i.type == "i64"
              set(i.results[0])
            when :sadd_overflow, :ssub_overflow then emit_overflow(i)
            when :smul_overflow then emit_smul_overflow(i)
            when :brif then emit_brif(i)
            when :switch then emit_switch(i)
            when :jump then emit_jump(i)
            when :return
              epilogue
              get(i.args[0]) unless i.args.empty?
              @code << "\x0F".b
            else
              raise Refused, "no wasm lowering for #{i.op}"
            end
          end
        end
      end
    end
  end
end
