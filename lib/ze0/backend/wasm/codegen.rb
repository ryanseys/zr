# frozen_string_literal: true

require_relative "../../backend"
require_relative "../../ir/function"
require_relative "../../obj/model"
require_relative "locals"

module Ze0
  module Backend
    module Wasm
      # The wasm32 emitter: IR functions and data objects to one WASI module.
      #
      # Every value is kept in a local of its type, shared with values whose
      # lives do not overlap (Locals; an i8 is an i32 local; an i64
      # stays i64, so a pointer is a 64-bit value whose address wraps to 32
      # bits at every memory access). Control flow is one `loop` around a
      # ladder of `block`s and a `br_table` on a block-index local: each IR
      # block sets the index of its successor and branches to the loop.
      # Stack slots live in a shadow stack in linear memory under a global
      # stack pointer. The module answers a floor of libc calls itself
      # where no function defines them (`FLOOR`): `malloc` bumps a heap
      # pointer above the shadow stack and grows the memory, `free` does
      # nothing, and `write` and `exit` become `fd_write` and `proc_exit`,
      # for a unit with no OS layer. The OS layer, rt/kernel/os/wasi, answers
      # every other call over its own imports. A function's address is its
      # index in the one table, from 1 so that a pointer is never zero;
      # `call_indirect` goes through that table.
      class Codegen
        class Refused < Backend::Refused; end

        PAGE = 65_536
        # The bottom of linear memory: the iovec scratch, then data objects,
        # then the shadow stack growing up from its base.
        SCRATCH = 16
        DATA_BASE = 32
        STACK_PAGES = 16
        # Data objects at most this many bytes apart share a segment.
        # wasmtime 48 checks each segment against its own alias region in a
        # module's startup function, and a function holds at most 65,535
        # regions; wasm itself allows 100,000 segments.
        SEGMENT_GAP = 16

        TYPE = { "i8" => 0x7F, "i32" => 0x7F, "i64" => 0x7E, "f64" => 0x7C }.freeze
        OP = {
          "i32" => { const: 0x41, add: 0x6A, sub: 0x6B, mul: 0x6C, div_s: 0x6D, div_u: 0x6E, rem_s: 0x6F, rem_u: 0x70,
                     and: 0x71, or: 0x72, xor: 0x73, shl: 0x74, shr_s: 0x75, shr_u: 0x76,
                     eq: 0x46, ne: 0x47, lt_s: 0x48, lt_u: 0x49, gt_s: 0x4A, gt_u: 0x4B, le_s: 0x4C, le_u: 0x4D, ge_s: 0x4E, ge_u: 0x4F },
          "i64" => { const: 0x42, add: 0x7C, sub: 0x7D, mul: 0x7E, div_s: 0x7F, div_u: 0x80, rem_s: 0x81, rem_u: 0x82,
                     and: 0x83, or: 0x84, xor: 0x85, shl: 0x86, shr_s: 0x87, shr_u: 0x88,
                     eq: 0x51, ne: 0x52, lt_s: 0x53, lt_u: 0x54, gt_s: 0x55, gt_u: 0x56, le_s: 0x57, le_u: 0x58, ge_s: 0x59, ge_u: 0x5A }
        }.freeze
        # The libc calls a module answers itself, where no function of the
        # name is defined: memory, which only the module can own, and the
        # calls a unit with no OS layer makes to write, leave and stop.
        FLOOR = { "write" => [[0x7F, 0x7E, 0x7E], [0x7E]], "exit" => [[0x7F], []], "_exit" => [[0x7F], []], "abort" => [[], []],
                  "malloc" => [[0x7E], [0x7E]], "free" => [[0x7E], []], "posix_memalign" => [[0x7E, 0x7E, 0x7E], [0x7F]],
                  "memmove" => [[0x7E, 0x7E, 0x7E], [0x7E]], "memset" => [[0x7E, 0x7F, 0x7E], [0x7E]] }.freeze

        WASI = "wasi_snapshot_preview1"
        # An import: the module it comes from, its name, and its wasm
        # parameter and result types.
        Import = Struct.new(:from, :name, :params, :results)
        # The imports the floor and `_start` call, which a module carries
        # whatever its functions import.
        OWN_IMPORTS = [Import.new(WASI, "fd_write", [0x7F, 0x7F, 0x7F, 0x7F], [0x7F]),
                       Import.new(WASI, "proc_exit", [0x7F], [])].freeze

        # How many i32 locals a shim body declares.
        LOCALS = { "malloc" => 1 }.freeze

        COND = { "eq" => :eq, "ne" => :ne, "slt" => :lt_s, "sle" => :le_s, "sgt" => :gt_s, "sge" => :ge_s,
                 "ult" => :lt_u, "ule" => :le_u, "ugt" => :gt_u, "uge" => :ge_u }.freeze

        # The runtime's half of a module, emitted once and kept: its
        # function names and signatures, their bodies, the types they use,
        # its data placed and patched, its table, and the symbols it names
        # that a program defines, at the indices and addresses promised to
        # its bodies. A program's module lays its own part after this one
        # and must honour the promises (`pending`).
        Prelude = Struct.new(:imports, :shims, :sigs, :bodies, :types, :data_at, :data_end, :segments, :table, :pending) do
          # `pending`: `{ functions: [names], data: { name => address } }`.
          def functions = sigs.keys
        end

        # `prelude`: a Prelude this module extends. `pending`: when emitting
        # a prelude, the function names and the data names another module
        # will define, in the order it must define them.
        def initialize(functions, data, prelude: nil, pending: nil)
          @functions = functions
          @data = data
          @prelude = prelude
          @pending = pending
        end

        # A Prelude of these functions and data, for modules to extend.
        def prelude
          layout
          bodies = @functions.map { |f| Body.new(self, f).emit }
          Prelude.new(@imports, @shims, @functions.to_h { |f| [f.name, signature(f)] }, bodies, @types, @data_at, @data_end,
                      @data.reject { |d| d.section == :bss }.map { |d| [@data_at[d.name], patched(d)] }, @table, @promised)
        end

        # The module's bytes.
        def emit
          layout
          pre = @prelude
          raise Refused, "no _start without a prelude or a main" unless pre || @functions.any? { |f| f.name == "main" }

          @index["_start"] = @index.size
          own = @functions.map { |f| Body.new(self, f).emit }
          bodies = @shims.map { |name| shim(name) } + (pre ? pre.bodies : []) + own + [start_body]
          sigs = (pre ? pre.sigs.values : []) + @functions.map { |f| signature(f) } + [[[], []]]
          shim_sigs = @shims.map { |name| FLOOR.fetch(name) }
          (@imports.map { |i| [i.params, i.results] } + shim_sigs + sigs).each { |t| type_index(t) }

          out = +"\0asm\x01\0\0\0".b
          out << section(1, vec(@types.map { |p, r| "\x60".b + vec(p.map(&:chr)) + vec(r.map(&:chr)) }))
          out << section(2, vec(@imports.map { |i| name(i.from) + name(i.name) + "\0".b + leb(type_index([i.params, i.results])) }))
          out << section(3, vec((shim_sigs + sigs).map { |t| leb(type_index(t)) }))
          out << section(4, vec(["\x70\x00".b + leb(@table.size + 1)])) unless @table.empty?
          stack_base = align(@data_end, 16)
          heap_base = align(stack_base + (STACK_PAGES * PAGE), 16)
          out << section(5, vec(["\0".b + leb((heap_base / PAGE) + 2)]))
          out << section(6, vec(["\x7F\x01".b + "\x41".b + sleb(stack_base) + "\x0B".b,
                                 "\x7F\x01".b + "\x41".b + sleb(heap_base) + "\x0B".b]))
          out << section(7, vec([name("memory") + "\x02".b + leb(0), name("_start") + "\0".b + leb(@index["_start"])]))
          out << section(9, vec(["\0".b + i32c(1) + "\x0B".b + vec(@table.map { |n| leb(function_index(n)) })])) unless @table.empty?
          out << section(10, vec(bodies))
          placed = (pre ? pre.segments : []) + @data.reject { |d| d.section == :bss }.map { |d| [@data_at[d.name], patched(d)] }
          out << section(11, vec(segments(placed).map { |at, bytes| "\0".b + "\x41".b + sleb(at) + "\x0B".b + vec_bytes(bytes) }))
          out
        end

        # The active data segments for `[address, bytes]` objects: objects
        # closer than SEGMENT_GAP bytes share one segment, with zeros between
        # them.
        def segments(placed)
          placed.sort_by(&:first).each_with_object([]) do |(at, bytes), runs|
            run = runs.last
            gap = run && at - (run[0] + run[1].bytesize)
            if gap && gap <= SEGMENT_GAP
              run[1] << ("\0".b * gap) << bytes
            else
              runs << [at, bytes.b]
            end
          end
        end

        # Function index space: imports first, then the shims, then the
        # prelude's functions, then ours (the prelude's pending ones first,
        # where it promised them). Data after the prelude's, the pending
        # objects first, at the addresses promised. Imports, shims, types
        # and the table continue the prelude's.
        def layout
          pre = @prelude
          @imports = pre ? pre.imports : imports
          if pre
            extra = imported.map(&:name) - @imports.map(&:name)
            raise Refused, "the prelude does not import #{extra.join(", ")}" unless extra.empty?
          end
          @shims = pre ? pre.shims : FLOOR.keys - @functions.map(&:name) - (@pending ? @pending[:functions] : [])
          @index = {}
          @imports.each_with_index { |import, i| @index[import.name] = i }
          @shims.each { |name| @index[name] = @index.size }
          pre&.functions&.each { |name| @index[name] = @index.size }
          if pre
            missing = pre.pending[:functions] - @functions.map(&:name)
            raise Refused, "the prelude waits for #{missing.join(", ")}" unless missing.empty?

            first = pre.pending[:functions]
            @functions = @functions.sort_by.with_index { |f, i| [first.index(f.name) || first.size, i] }
          end
          # Initialized data before bss, so that the bytes a module writes
          # are one run and not one segment between each two zero objects.
          first = pre ? pre.pending[:data].keys : []
          @data = @data.sort_by.with_index { |d, i| [first.index(d.name) || first.size, d.section == :bss ? 1 : 0, i] }
          @functions.each { |f| @index[f.name] = @index.size }
          @types = pre ? pre.types.dup : []
          place_data(pre ? pre.data_end : DATA_BASE, pre ? pre.data_at.dup : {})
          pre&.pending&.[](:data)&.each do |name, at|
            raise Refused, "#{name} is at #{@data_at[name].inspect}, not the #{at} the prelude promised" unless @data_at[name] == at
          end

          used = (@functions.flat_map { |f| f.callees.map(&:symbol) } - @index.keys).uniq
          promise(used)
          unknown = used - @shims - @promised[:functions]
          raise Refused, "no wasm shim for #{unknown.join(", ")}" unless unknown.empty?

          taken = @functions.flat_map { |f| f.blocks.flat_map(&:insts).select { |i| i.op == :func_addr }.map { |i| f.callees.find { |c| c.fn == i.args[0] }.symbol } }
          named = @data.flat_map { |d| d.relocs.map(&:symbol) }.select { |name| @index.key?(name) }
          @table = ((pre ? pre.table : []) + taken + named).uniq
        end

        # The module's own imports, then each its functions name, in the
        # order they first do.
        def imports
          (OWN_IMPORTS + imported).each_with_object({}) do |import, by_name|
            known = by_name[import.name] ||= import
            raise Refused, "#{import.name} is imported as #{known.to_a.inspect} and #{import.to_a.inspect}" unless known == import
          end.values
        end

        # What the functions import, as the IR signature of each call says.
        def imported
          @functions.flat_map do |f|
            f.callees.select(&:from).map do |c|
              params, results = sig_type(f.sigs.find { |s| s.sig == c.sig })
              Import.new(c.from, c.symbol, params, results)
            end
          end
        end

        # When emitting a prelude, the pending functions take the indices
        # right after ours, and the pending data the addresses right after
        # ours, each eight bytes wide but the last, which may be any size.
        def promise(used)
          @promised = { functions: [], data: {} }
          return unless @pending

          @pending[:functions].each { |name| @index[name] = @index.size }
          @promised[:functions] = @pending[:functions]
          at = @data_end
          @pending[:data].each do |name|
            at = align(at, 8)
            @promised[:data][name] = at
            @data_at[name] = at
            at += 8
          end
        end

        def signature(f)
          [f.params.map { |t| TYPE.fetch(t.split.first) }, f.ret_type ? [TYPE.fetch(f.ret_type)] : []]
        end

        def type_index(t)
          @types.index(t) || (@types << t).size - 1
        end

        def function_index(name)
          @index.fetch(name) { raise Refused, "no function named #{name}" }
        end

        # The wasm parameter and result types a call to `name` must match;
        # nil for a function this module has not seen.
        def function_type(name)
          return FLOOR[name] if @shims.include?(name)
          return @prelude.sigs[name] if @prelude&.sigs&.key?(name)

          @function_named ||= @functions.to_h { |x| [x.name, x] }
          f = @function_named[name]
          return signature(f) if f

          @imports.find { |import| import.name == name }&.then { |import| [import.params, import.results] }
        end

        # The table index that stands for `name`'s address.
        def table_index(name)
          @table.index(name) + 1
        end

        # The wasm type of an IR signature.
        def sig_type(s)
          [s.params.map { |t| TYPE.fetch(t) }, s.ret ? [TYPE.fetch(s.ret)] : []]
        end

        # A data object's bytes with every absolute relocation filled in: a
        # function's address is its table index, as `func_addr` answers.
        def patched(d)
          bytes = d.bytes.dup
          d.relocs.each do |r|
            raise Refused, "#{d.name}: a #{r.kind} relocation in data" unless r.kind == :abs64

            address = @index.key?(r.symbol) ? table_index(r.symbol) : data_address(r.symbol)
            bytes[r.offset, 8] = [address + r.addend].pack("Q<")
          end
          bytes
        end

        def data_address(name)
          @data_at.fetch(name) { raise Refused, "no data named #{name}" }
        end

        def place_data(at, placed)
          @data_at = placed
          @data.each do |d|
            at = align(at, [d.align, 1].max)
            @data_at[d.name] = at
            at += d.size
          end
          @data_end = at
        end

        # `write(fd, ptr, len)`: an iovec in the scratch area, then fd_write.
        def shim(name)
          code = +"".b
          case name
          when "write"
            # iov.buf = ptr, iov.len = len (both i32 in memory)
            code << i32c(SCRATCH) << "\x20\x01".b << "\xA7".b << "\x36\x02\x00".b
            code << i32c(SCRATCH) << "\x20\x02".b << "\xA7".b << "\x36\x02\x04".b
            code << "\x20\x00".b << i32c(SCRATCH) << i32c(1) << i32c(SCRATCH + 8) << "\x10".b << leb(function_index("fd_write")) << "\x1A".b
            code << i32c(SCRATCH + 8) << "\x28\x02\x00".b << "\xAD".b
          when "exit", "_exit"
            code << "\x20\x00".b << "\x10".b << leb(function_index("proc_exit"))
          when "abort"
            code << "\x00".b
          when "malloc"
            # r = heap; heap += n rounded to 16; grow when heap passes the
            # memory's end; answer r.
            code << "\x23\x01".b << "\x21\x01".b
            code << "\x23\x01".b << "\x20\x00".b << "\xA7".b << i32c(15) << "\x6A".b << i32c(-16) << "\x71".b << "\x6A".b << "\x24\x01".b
            code << "\x23\x01".b << "\x3F\x00".b << i32c(16) << "\x74".b << "\x4B".b
            code << "\x04\x40".b
            code << "\x23\x01".b << "\x3F\x00".b << i32c(16) << "\x74".b << "\x6B".b << i32c(PAGE - 1) << "\x6A".b << i32c(16) << "\x76".b
            code << "\x40\x00".b << "\x1A".b
            code << "\x0B".b
            code << "\x20\x01".b << "\xAD".b
          when "posix_memalign"
            # *slot = (malloc(size + align) + align - 1) & -align; answer 0.
            # The heap never gives memory back, so the slack costs nothing.
            code << "\x20\x00".b << "\xA7".b
            code << "\x20\x01".b << "\x20\x02".b << "\x7C".b << "\x10".b << leb(function_index("malloc"))
            code << "\x20\x01".b << "\x7C".b << "\x42\x01".b << "\x7D".b
            code << "\x42\x00".b << "\x20\x01".b << "\x7D".b << "\x83".b
            code << "\x37\x03\x00".b << "\x41\x00".b
          when "free"
            code << "".b
          when "memmove"
            # memory.copy handles ranges that overlap; answer the destination.
            code << "\x20\x00\xA7\x20\x01\xA7\x20\x02\xA7".b << "\xFC\x0A\x00\x00".b << "\x20\x00".b
          when "memset"
            # memory.fill with the low byte of c; answer the destination.
            code << "\x20\x00\xA7\x20\x01\x20\x02\xA7".b << "\xFC\x0B\x00".b << "\x20\x00".b
          end
          code << "\x0B".b
          n = LOCALS[name]
          vec_bytes(vec(n ? [leb(n) + "\x7F".b] : []) + code)
        end

        # `_start`: main(0, 0), then proc_exit with what it answered.
        def start_body
          params, results = function_type("main")
          raise Refused, "no main" unless params
          code = +"".b
          params.each { |t| code << (t == 0x7E ? "\x42\x00".b : "\x41\x00".b) }
          code << "\x10".b << leb(function_index("main"))
          code << (results.first == 0x7E ? "\xA7".b : "".b) unless results.empty?
          code << (results.empty? ? i32c(0) : "".b)
          code << "\x10".b << leb(function_index("proc_exit")) << "\x0B".b
          vec_bytes(vec([]) + code)
        end

        # --- encoding ---------------------------------------------------

        def leb(n)
          out = +"".b
          loop do
            byte = n & 0x7F
            n >>= 7
            if n.zero?
              out << byte.chr
              return out
            end
            out << (byte | 0x80).chr
          end
        end

        def sleb(n)
          out = +"".b
          loop do
            byte = n & 0x7F
            n >>= 7
            done = (n.zero? && (byte & 0x40).zero?) || (n == -1 && (byte & 0x40) != 0)
            out << (done ? byte : byte | 0x80).chr
            return out if done
          end
        end

        def i32c(n)
          "\x41".b + sleb(n)
        end

        def vec(items)
          leb(items.size) + items.join
        end

        def vec_bytes(bytes)
          leb(bytes.bytesize) + bytes
        end

        def name(s)
          vec_bytes(s.b)
        end

        def section(id, payload)
          id.chr + vec_bytes(payload)
        end

        def align(n, a)
          (n + a - 1) & ~(a - 1)
        end

        # One function's body.
        class Body
          # Past this many blocks a function is dispatched in two steps,
          # in groups of the same size. Measured on the shape ze0 emits, a
          # group of 256 is the cheapest to compile at every size tried --
          # 8,000 blocks take 20.0 s in groups of 128, 9.9 s in groups of
          # 256, 11.3 s in 512 -- and the square root the count suggests
          # is well off it.
          LADDER = 256
          WIDTH = Integer(ENV.fetch("ZE0_WASM_WIDTH", LADDER))

          def initialize(mod, f)
            @m = mod
            @f = f
            @local = {}
            @type = {}
            @code = +"".b
          end

          def emit
            assign
            prologue
            dispatch
            @code << "\x0B".b
            locals = @locals.chunk_while { |a, b| a == b }.map { |run| @m.leb(run.size) + run.first.chr }
            @m.vec_bytes(@m.vec(locals) + @code)
          end

          private

          # Parameters first, then the shared locals every other value is
          # kept in, then the block index and the frame base. A constant has
          # no local: it is written where it is read (`CONSTANTS`).
          def assign
            n = 0
            @const = {}
            @f.blocks.each { |b| b.params.each { |v, t| @type[v] = t } }
            @f.blocks.first.params.each { |v, _| @local[v] = n; n += 1 }
            values = []
            @f.blocks.each_with_index do |b, bi|
              b.params.each { |v, t| values << [v, Codegen::TYPE.fetch(t)] unless bi.zero? }
              b.insts.each do |i|
                i.results.each_with_index do |v, k|
                  @type[v] = result_type(i, k)
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
            @slot_at = @f.slots.map { |s| off = @m.align(off, [s.align, 8].max); at = off; off += s.bytes; at }
            @frame = @m.align(off, 16)
          end

          def result_type(i, k)
            case i.op
            when :iconst, :load, :ireduce, :uextend, :sextend then i.type
            when :call then sig_named(callee(i.callee).sig).ret
            when :call_indirect then sig_named(i.callee).ret
            when :icmp, :fcmp then "i8"
            when :stack_addr, :symbol_value, :func_addr then "i64"
            when *IR::Inst::FBINOPS, *IR::Inst::FUNOPS then "f64"
            when :select then @type[i.args[1]]
            when :sadd_overflow, :ssub_overflow, :smul_overflow then k.zero? ? @type[i.args[0]] : "i8"
            else i.type || @type[i.args[0]]
            end
          end

          # Each by its key, the first row winning as `find` would.
          def callee(fn)
            @callee ||= @f.callees.each_with_object({}) { |c, index| index[c.fn] ||= c }
            @callee[fn]
          end

          def sig_named(sig)
            @sig_named ||= @f.sigs.each_with_object({}) { |s, index| index[s.sig] ||= s }
            @sig_named[sig]
          end

          def global(gv)
            @global ||= @f.globals.each_with_object({}) { |g, index| index[g.gv] ||= g }
            @global[gv]
          end

          def block_named(name)
            @block_named ||= @f.blocks.each_with_object({}) { |b, index| index[b.name] ||= b }
            @block_named[name]
          end

          def wide?(v)
            @type.fetch(v) == "i64"
          end

          # A division, as the IR says it answers (lib/ze0/ir/inst.rb): by
          # zero, `udiv`/`sdiv` answer 0 and `urem`/`srem` the dividend; the
          # most negative number over -1 wraps. wasm's own `div` traps on
          # both, so each is guarded. `rem_s` of that pair answers 0, as the
          # IR does, and needs no guard.
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
            @code << table.fetch({ udiv: :div_u, sdiv: :div_s, urem: :rem_u, srem: :rem_s }[i.op]).chr
            @code << "\x0B".b if i.op == :sdiv
            @code << "\x0B".b
            set(i.results[0])
          end

          def ops(v)
            Codegen::OP.fetch(wide?(v) ? "i64" : "i32")
          end

          def get(v)
            i = @const[v]
            return constant(i) if i

            @code << "\x20".b << @m.leb(@local.fetch(v))
          end

          # The instructions whose value is known without running anything,
          # or from the frame base alone: read where they are used, they need
          # no local, and the constants and slot addresses a function makes in
          # its entry block are not live across every block after it. That
          # life is most of what sharing locals costs.
          CONSTANTS = %i[iconst symbol_value func_addr stack_addr].freeze

          def constant(i)
            case i.op
            when :iconst
              # A constant written unsigned wraps to its signed bits.
              n = i.args[0]
              n -= 1 << 64 if i.type == "i64" && n >= 1 << 63
              n -= 1 << 32 if i.type != "i64" && n >= 1 << 31
              @code << (i.type == "i64" ? "\x42".b : "\x41".b) << @m.sleb(n)
            when :symbol_value
              @code << "\x42".b << @m.sleb(@m.data_address(global(i.args[0]).symbol))
            when :func_addr
              @code << "\x42".b << @m.sleb(@m.table_index(callee(i.args[0]).symbol))
            when :stack_addr
              @code << "\x20".b << @m.leb(@fp) << @m.i32c(@slot_at[Integer(i.args[0].delete_prefix("ss"))]) << "\x6A".b << "\xAD".b
            end
          end

          def set(v)
            @code << "\x21".b << @m.leb(@local.fetch(v))
          end

          # The frame: global 0 is the stack pointer, saved in the frame
          # base local and bumped past the slots.
          def prologue
            @code << "\x23\x00".b << "\x22".b << @m.leb(@fp)
            @code << @m.i32c(@frame) << "\x6A".b << "\x24\x00".b
            @code << @m.i32c(0) << "\x21".b << @m.leb(@bb)
          end

          def epilogue
            @code << "\x20".b << @m.leb(@fp) << "\x24\x00".b
          end

          # loop { block ... block { br_table } body0 end body1 end ... }
          # The blocks, each reached by branching out of the `block` that
          # ends where it begins. A ladder of N of them nests N deep, and a
          # wasm compiler spends time on that depth that grows with its
          # square: 1,000 blocks take 0.2 s and 14,000 take 78. The core
          # library has one function of 14,793 -- the table
          # UnicodeNormalize builds -- so a function past LADDER blocks
          # takes two steps instead: the index picks a group, and the
          # group picks the block. The deepest nesting is then about twice
          # the square root of the count.
          def dispatch
            n = @f.blocks.size
            @code << "\x03\x40".b
            if n <= LADDER
              ladder(@f.blocks, 0, 0)
            else
              @width = WIDTH
              groups = @f.blocks.each_slice(@width).to_a
              @groups = groups.size
              groups.size.times { @code << "\x02\x40".b }
              @code << "\x20".b << @m.leb(@bb) << @m.i32c(@width) << "\x6E".b
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
            # Every block ends in a branch or a return; the loop's end is
            # never reached, and `unreachable` tells the validator so.
            @code << "\x00".b
          end

          # One run of blocks under a `br_table` of its own. `first` is the
          # index its first block carries, and `outer` how many constructs
          # stand between this run's loop and the function's own, which is
          # nothing when the run is the whole function.
          def ladder(blocks, first, outer)
            m = blocks.size
            m.times { @code << "\x02\x40".b }
            @code << "\x20".b << @m.leb(@bb)
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

          # `br_table` over `count` labels, the first of them the default:
          # an index past the end cannot happen, since every branch names
          # a block of this function.
          def table(count)
            @code << "\x0E".b << @m.leb(count)
            count.times { |i| @code << @m.leb(i) }
            @code << @m.leb(0)
          end

          # A branch to `name`: the block index, then a branch to the
          # `br_table` that reads it -- this run's own loop when the block
          # is in this run, and the function's loop when it is not.
          #
          # Leaving the `block` that ends where a later block begins would
          # reach that block directly, and cost no index at all. Measured,
          # it is between 8 and 20 times slower to compile: 2,000 blocks
          # take 0.24 s this way and 4.93 s that way. So every branch goes
          # through a `br_table`.
          def go(name)
            at = @f.blocks.index { |b| b.name == name }
            @code << @m.i32c(at) << "\x21".b << @m.leb(@bb)
            @code << "\x0C".b << @m.leb((@span - 1 - @row + @bias) + reach(at))
          end

          # How much further than this group's own loop a branch to the
          # block at `at` has to go. Nothing, when the block is in this
          # group. A group ahead of this one is a `block` this one sits
          # inside, so leaving it reaches that group's own `br_table` --
          # which is what keeps the function's one loop from gathering a
          # predecessor for every branch that leaves its group. Only a
          # branch to a group behind this one goes all the way out.
          def reach(at)
            return 0 if @group.cover?(at)

            ahead = (at / @width) - @gk
            ahead.positive? ? ahead : @outer
          end

          def emit_inst(i)
            case i.op
            when *CONSTANTS
              # Written where it is read.
              nil
            when :load
              get(i.args[0])
              @code << "\xA7".b
              @code << { "i64" => "\x29\x03".b, "i32" => "\x28\x02".b, "i8" => "\x2D\x00".b, "f64" => "\x2B\x03".b }.fetch(i.type) << @m.leb(i.offset)
              set(i.results[0])
            when :store
              get(i.args[1])
              @code << "\xA7".b
              get(i.args[0])
              @code << { "i64" => "\x37\x03".b, "i32" => "\x36\x02".b, "i8" => "\x3A\x00".b, "f64" => "\x39\x03".b }.fetch(@type[i.args[0]]) << @m.leb(i.offset)
            when :call_indirect
              ptr, *args = i.args
              args.each { |a| get(a) }
              get(ptr)
              @code << "\xA7".b
              _params, results = @m.sig_type(sig_named(i.callee))
              @code << "\x11".b << @m.leb(@m.type_index([_params, results])) << "\x00".b
              if i.results.empty?
                # An answer the instruction does not take is dropped.
                @code << "\x1A".b unless results.empty?
              else
                set(i.results[0])
              end
            when :call
              # A libc call's text signature may say i64 where the floor
              # takes i32: the width follows the callee.
              name = callee(i.callee).symbol
              params, results = @m.function_type(name) || @m.sig_type(sig_named(callee(i.callee).sig))
              i.args.zip(params).each do |a, want|
                get(a)
                @code << "\xA7".b if wide?(a) && want == 0x7F
                @code << "\xAD".b if !wide?(a) && want == 0x7E && @type[a] != "f64"
              end
              @code << "\x10".b << @m.leb(@m.function_index(name))
              if i.results.empty?
                # An answer the text does not name is dropped.
                @code << "\x1A".b unless results.empty?
              else
                @code << "\xA7".b if results.first == 0x7E && !wide?(i.results[0])
                @code << "\xAD".b if results.first == 0x7F && wide?(i.results[0])
                set(i.results[0])
              end
            when :icmp
              get(i.args[0])
              get(i.args[1])
              @code << ops(i.args[0]).fetch(Codegen::COND.fetch(i.cond)).chr
              set(i.results[0])
            when :fcmp
              get(i.args[0])
              get(i.args[1])
              @code << { "eq" => 0x61, "ne" => 0x62, "lt" => 0x63, "gt" => 0x64, "le" => 0x65, "ge" => 0x66 }.fetch(i.cond).chr
              set(i.results[0])
            when *IR::Inst::FBINOPS
              get(i.args[0])
              get(i.args[1])
              @code << { fadd: 0xA0, fsub: 0xA1, fmul: 0xA2, fdiv: 0xA3 }.fetch(i.op).chr
              set(i.results[0])
            when *IR::Inst::FUNOPS
              get(i.args[0])
              @code << { fabs: 0x99, fneg: 0x9A, ceil: 0x9B, floor: 0x9C, trunc: 0x9D, nearest: 0x9E, sqrt: 0x9F }.fetch(i.op).chr
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
            when :iadd, :isub, :imul, :band, :bor, :bxor, :ishl, :ushr, :sshr
              get(i.args[0])
              get(i.args[1])
              @code << ops(i.args[0]).fetch({ iadd: :add, isub: :sub, imul: :mul,
                                              band: :and, bor: :or, bxor: :xor, ishl: :shl, ushr: :shr_u, sshr: :shr_s }[i.op]).chr
              set(i.results[0])
            when :select
              get(i.args[1])
              get(i.args[2])
              get(i.args[0])
              # A wide condition is tested, not wrapped: any nonzero
              # value selects the first operand.
              @code << "\x50".b << "\x45".b if wide?(i.args[0])
              @code << "\x1B".b
              set(i.results[0])
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
            when :sadd_overflow, :ssub_overflow
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
            when :smul_overflow
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
              @code << "\x42".b << @m.sleb(-(2**63)) << "\x51".b
              @code << "\x05".b
              get(i.results[0])
              get(i.args[0])
              @code << "\x7F".b
              get(i.args[1])
              @code << "\x52".b
              @code << "\x0B\x0B".b
              set(i.results[1])
            when :brif
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
            when :jump
              name, args = i.targets[0]
              params = block_named(name).params
              args.each { |a| get(a) }
              args.each_index.reverse_each { |k| set(params[k][0]) }
              go(name)
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
