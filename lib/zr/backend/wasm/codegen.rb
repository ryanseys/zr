# frozen_string_literal: true

require_relative "../../backend"
require_relative "../../ir/function"
require_relative "../../ir/types"
require_relative "../../obj/model"
require_relative "body"
require_relative "shims"
require_relative "../../config"
require_relative "../../bytes"

module Zr
  module Backend
    module Wasm
      # The wasm32 emitter: writes IR functions and data objects as one WASI module.
      #
      # Values: each value is in a local of its type (`Locals`). Values whose
      # live ranges do not overlap share a local. An i8 uses an i32 local. An
      # i64 stays i64, so a pointer is 64 bits and wraps to 32 bits at each
      # memory access.
      #
      # Control flow: one `loop` around nested `block`s and a `br_table` on a
      # block-index local. Each IR block sets the index of its successor and
      # branches to the loop. Stack slots are in a shadow stack in linear
      # memory, below a global stack pointer.
      #
      # `LIBC_SHIMS`: the module defines some libc calls when no function
      # defines them. `malloc` increments a heap pointer above the shadow
      # stack and grows the memory, `free` does nothing, and `write` and
      # `exit` become `fd_write` and `proc_exit` for a unit with no OS layer.
      # The OS layer, runtime/kernel/os/wasi, implements every other call with
      # its own imports. A function's address is its index in the one table,
      # starting at 1 so that a pointer is never zero. `call_indirect` uses that table.
      class Codegen
        class Refused < Backend::Refused; end

        PAGE = 65_536
        # The bottom of linear memory: the iovec scratch, then data objects,
        # then the shadow stack growing up from its base.
        SCRATCH = 16
        DATA_BASE = 32
        STACK_PAGES = 16
        # Data objects at most this many bytes apart share a segment.
        # wasmtime 48 checks each segment against its own alias region in the
        # module's startup function, and a function can have at most 65,535
        # regions. wasm itself allows 100,000 segments.
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

        WASI = "wasi_snapshot_preview1"
        # An import: the module it comes from, its name, and its wasm
        # parameter and result types.
        Import = Data.define(:from, :name, :params, :results)
        # The imports that the libc shims and `_start` call. Every module
        # includes them, whatever its functions import.
        OWN_IMPORTS = [Import.new(WASI, "fd_write", [0x7F, 0x7F, 0x7F, 0x7F], [0x7F]),
                       Import.new(WASI, "proc_exit", [0x7F], [])].freeze

        COND = { "eq" => :eq, "ne" => :ne, "slt" => :lt_s, "sle" => :le_s, "sgt" => :gt_s, "sge" => :ge_s,
                 "ult" => :lt_u, "ule" => :le_u, "ugt" => :gt_u, "uge" => :ge_u }.freeze

        # The runtime part of a module, emitted one time and kept. It contains
        # the function names and signatures, their bodies, the types they use,
        # the placed and patched data, the table, and the symbols that it refers
        # to but a program defines. Those symbols have fixed indices and
        # addresses (`pending`). A program's module puts its own part after
        # this one and must define those symbols at those positions.
        Prelude = Data.define(:imports, :shims, :sigs, :bodies, :types, :data_at, :data_end, :segments, :table,
                              :pending) do
          def functions = sigs.keys
        end

        # `prelude`: a Prelude that this module extends. `pending`: when this
        # emits a prelude, the function and data names that another module
        # defines, in the order that it must define them.
        def initialize(functions, data, prelude: nil, pending: nil)
          @functions = functions
          @data = data
          @prelude = prelude
          @pending = pending
        end

        # Returns a Prelude of these functions and data, for modules to extend.
        def prelude
          layout
          bodies = @functions.map { |f| Body.new(self, f).emit }
          Prelude.new(@imports, @shims, @functions.to_h { |f| [f.name, signature(f)] }, bodies, @types, @data_at, @data_end,
                      @data.reject { |d| d.section == :bss }.map { |d| [@data_at[d.name], patched(d)] }, @table, @promised)
        end

        # Returns the module's bytes.
        def emit
          layout
          pre = @prelude
          raise Refused, "no _start without a prelude or a main" unless pre || @functions.any? { |f| f.name == "main" }

          @index["_start"] = @index.size
          own = @functions.map { |f| Body.new(self, f).emit }
          bodies = @shims.map { |name| shim(name) } + (pre ? pre.bodies : []) + own + [start_body]
          sigs = (pre ? pre.sigs.values : []) + @functions.map { |f| signature(f) } + [[[], []]]
          shim_sigs = @shims.map { |name| LIBC_SHIMS.fetch(name) }
          (@imports.map { |i| [i.params, i.results] } + shim_sigs + sigs).each { |t| type_index(t) }

          out = +"\0asm\x01\0\0\0".b
          out << section(1, vec(@types.map { |p, r| "\x60".b + vec(p.map(&:chr)) + vec(r.map(&:chr)) }))
          out << section(2, vec(@imports.map { |i| name(i.from) + name(i.name) + "\0".b + leb(type_index([i.params, i.results])) }))
          out << section(3, vec((shim_sigs + sigs).map { |t| leb(type_index(t)) }))
          out << section(4, vec(["\x70\x00".b + leb(@table.size + 1)])) unless @table.empty?
          stack_base = Bytes.align(@data_end, 16)
          heap_base = Bytes.align(stack_base + (STACK_PAGES * PAGE), 16)
          out << section(5, vec(["\0".b + leb((heap_base / PAGE) + 2)]))
          # Global 0 is the shadow stack pointer, 1 the heap pointer, 2
          # the gate word (`IR::Inst::GATES`).
          out << section(6, vec(["\x7F\x01".b + "\x41".b + sleb(stack_base) + "\x0B".b,
                                 "\x7F\x01".b + "\x41".b + sleb(heap_base) + "\x0B".b,
                                 "\x7E\x01".b + "\x42\x00".b + "\x0B".b]))
          out << section(7, vec([name("memory") + "\x02".b + leb(0), name("_start") + "\0".b + leb(@index["_start"])]))
          out << section(9, vec(["\0".b + i32c(1) + "\x0B".b + vec(@table.map { |n| leb(function_index(n)) })])) unless @table.empty?
          out << section(10, vec(bodies))
          placed = (pre ? pre.segments : []) + @data.reject { |d| d.section == :bss }.map { |d| [@data_at[d.name], patched(d)] }
          out << section(11, vec(segments(placed).map { |at, bytes| "\0".b + "\x41".b + sleb(at) + "\x0B".b + vec_bytes(bytes) }))
          out << names_section if Config.current.wasm_names?
          out
        end

        # The function names, as a custom section. The program does not read
        # it, but wasmtime does: a trap then shows `zr_ivtab_append` in place
        # of `<wasm function 1097>`. It is as large as all symbol names, so
        # it is emitted only on request.
        def names_section
          rows = @index.sort_by(&:last).map { |symbol, index| leb(index) + name(symbol) }
          section(0, name("name") + section(1, vec(rows)))
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

        # Function index space: imports, then the shims, then the prelude's
        # functions, then this module's functions (the prelude's pending
        # ones first, at their fixed indices). Data comes after the prelude's
        # data, with the pending objects first at their fixed addresses.
        # Imports, shims, types and the table continue from the prelude's.
        def layout
          pre = @prelude
          @imports = pre ? pre.imports : imports
          if pre
            extra = imported.map(&:name) - @imports.map(&:name)
            raise Refused, "the prelude does not import #{extra.join(", ")}" unless extra.empty?
          end
          pending = @pending ? @pending[:functions] : []
          @shims = pre ? pre.shims : LIBC_SHIMS.keys - @functions.map(&:name) - pending
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
          # Initialized data comes before bss, so the written bytes are one
          # run, not one segment between each pair of zero objects.
          first = pre ? pre.pending[:data].keys : []
          @data = @data.sort_by.with_index { |d, i| [first.index(d.name) || first.size, d.section == :bss ? 1 : 0, i] }
          @functions.each { |f| @index[f.name] = @index.size }
          @types = pre ? pre.types.dup : []
          place_data(pre ? pre.data_end : DATA_BASE, pre ? pre.data_at.dup : {})
          pre&.pending&.[](:data)&.each do |name, at|
            raise Refused, "#{name} is at #{@data_at[name].inspect}, not the #{at} the prelude promised" unless @data_at[name] == at
          end

          used = (@functions.flat_map { |f| f.callees.map(&:symbol) } - @index.keys).uniq
          promise
          unknown = used - @shims - @promised[:functions]
          raise Refused, "no wasm shim for #{unknown.join(", ")}" unless unknown.empty?

          taken = @functions.flat_map { |f| f.blocks.flat_map(&:insts).select { |i| i.op == :func_addr }.map { |i| f.callees.find { |c| c.fn == i.args[0] }.symbol } }
          named = @data.flat_map { |d| d.relocs.map(&:symbol) }.select { |name| @index.key?(name) }
          @table = ((pre ? pre.table : []) + taken + named).uniq
        end

        # The module's own imports, then each import that its functions
        # refer to, in order of first use.
        def imports
          (OWN_IMPORTS + imported).each_with_object({}) do |import, by_name|
            known = by_name[import.name] ||= import
            raise Refused, "#{import.name} is imported as #{known.to_a.inspect} and #{import.to_a.inspect}" unless known == import
          end.values
        end

        # The imports of the functions, with types from the IR signature of each call.
        def imported
          @functions.flat_map do |f|
            f.callees.select(&:from).map do |c|
              params, results = sig_type(f.sigs.find { |s| s.sig == c.sig })
              Import.new(c.from, c.symbol, params, results)
            end
          end
        end

        # When this emits a prelude, the pending functions get the indices
        # directly after this module's functions. The pending data gets the
        # addresses directly after this module's data, 8 bytes each, except
        # the last, which can be any size.
        def promise
          @promised = { functions: [], data: {} }
          return unless @pending

          @pending[:functions].each { |name| @index[name] = @index.size }
          @promised[:functions] = @pending[:functions]
          at = @data_end
          @pending[:data].each do |name|
            at = Bytes.align(at, 8)
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

        # Returns the wasm parameter and result types for a call to `name`,
        # or nil for a function that this module does not know.
        def function_type(name)
          return LIBC_SHIMS[name] if @shims.include?(name)
          return @prelude.sigs[name] if @prelude&.sigs&.key?(name)

          @function_named ||= @functions.to_h { |x| [x.name, x] }
          f = @function_named[name]
          return signature(f) if f

          @imports.find { |import| import.name == name }&.then { |import| [import.params, import.results] }
        end

        # The table index that represents the address of `name`.
        def table_index(name)
          @table.index(name) + 1
        end

        # The wasm type of an IR signature.
        def sig_type(s)
          [s.params.map { |t| TYPE.fetch(t) }, s.ret ? [TYPE.fetch(s.ret)] : []]
        end

        # Returns a data object's bytes with every absolute relocation filled
        # in. A function's address is its table index, as for `func_addr`.
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
            at = Bytes.align(at, [d.align, 1].max)
            @data_at[d.name] = at
            at += d.size
          end
          @data_end = at
        end

        # `_start`: main(0, 0), then proc_exit with its return value.
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

        def leb(n) = Bytes.leb(n)

        def sleb(n) = Bytes.sleb(n)

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
      end
    end
  end
end
