# frozen_string_literal: true

require_relative "../../backend"
require_relative "../../ir/function"
require_relative "../../ir/types"
require_relative "../../obj/model"
require_relative "codegen/body"
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
      # The OS layer, lib/zr/runtime/kernel/os/wasi, implements every other call with
      # its own imports. A function's address is its index in the one table,
      # starting at 1 so that a pointer is never zero. `call_indirect` uses that table.
      class Codegen
        # @rbs @functions: Array[IR::Function]
        # @rbs @data: Array[Obj::Datum]
        # @rbs @prelude: Prelude?
        # @rbs @pending: pending?
        # @rbs @imports: Array[Import]
        # @rbs @shims: Array[String]
        # @rbs @index: Hash[String, Integer]
        # @rbs @types: Array[signature]
        # @rbs @type_at: Hash[signature, Integer]
        # @rbs @data_at: Hash[String, Integer]
        # @rbs @data_end: Integer
        # @rbs @table: Array[String]
        # @rbs @table_at: Hash[String, Integer]
        # @rbs @import_named: Hash[String, Import]
        # @rbs @promised: promised
        # @rbs @function_named: Hash[String, IR::Function]?
        # @rbs @slotted: Hash[String, signature]

        class Refused < Backend::Refused; end

        PAGE = 65_536
        # The bottom of linear memory: the iovec scratch, then data objects,
        # then the shadow stack growing up from its base.
        SCRATCH = 16
        DATA_BASE = 32
        STACK_PAGES = 16
        # Data objects at most this many bytes apart share a segment. wasm
        # allows 100,000 segments, and a module with eval support has about
        # 90,000 data objects. wasmtime 48 could not compile more than 65,535
        # segments; 49.0.2 compiles 70,000, but each segment is still a copy
        # at the module's start.
        SEGMENT_GAP = 16
        # The table slots that a runtime module (`runtime_module`) keeps
        # after its own entries, for the program module's.
        PROGRAM_SLOTS = 65_536
        # The module name that a program module imports the runtime under
        # (`wasmtime run --preload zr=<runtime>`).
        RUNTIME = "zr"
        # The custom section of a program module that names its runtime
        # module's file.
        RUNTIME_SECTION = "zr.runtime"
        # The custom section of a runtime module that names what zr links
        # a program against: zr's version, the target and the prelude's
        # key, as JSON (`runtime_module`). wasmtime skips it.
        LINK_SECTION = "zr.link"

        TYPE = { "i8" => 0x7F, "i32" => 0x7F, "i64" => 0x7E, "f64" => 0x7C }.freeze #: Hash[String, Integer]
        OP = {
          "i32" => { const: 0x41, add: 0x6A, sub: 0x6B, mul: 0x6C, div_s: 0x6D, div_u: 0x6E, rem_s: 0x6F, rem_u: 0x70,
                     and: 0x71, or: 0x72, xor: 0x73, shl: 0x74, shr_s: 0x75, shr_u: 0x76,
                     eq: 0x46, ne: 0x47, lt_s: 0x48, lt_u: 0x49, gt_s: 0x4A, gt_u: 0x4B, le_s: 0x4C, le_u: 0x4D, ge_s: 0x4E, ge_u: 0x4F },
          "i64" => { const: 0x42, add: 0x7C, sub: 0x7D, mul: 0x7E, div_s: 0x7F, div_u: 0x80, rem_s: 0x81, rem_u: 0x82,
                     and: 0x83, or: 0x84, xor: 0x85, shl: 0x86, shr_s: 0x87, shr_u: 0x88,
                     eq: 0x51, ne: 0x52, lt_s: 0x53, lt_u: 0x54, gt_s: 0x55, gt_u: 0x56, le_s: 0x57, le_u: 0x58, ge_s: 0x59, ge_u: 0x5A }
        }.freeze #: Hash[String, Hash[Symbol, Integer]]

        WASI = "wasi_snapshot_preview1"
        MAGIC = "\0asm\x01\0\0\0".b.freeze
        # Each global's export name and wasm type, in index order.
        GLOBALS = [["stack_pointer", 0x7F], ["heap_pointer", 0x7F], ["gate", 0x7E]].freeze #: Array[[String, Integer]]
        # An import: the module it comes from, its name, and its wasm
        # parameter and result types.
        # The fields of Import and Prelude are typed in
        # sig/zr/backend/wasm/codegen.rbs, the methods here.
        # @rbs skip
        Import = Data.define(:from, :name, :params, :results)

        class Import
          #: () -> signature
          def signature = [params, results]
        end

        # The imports that the libc shims and `_start` call. Every module
        # includes them, whatever its functions import.
        OWN_IMPORTS = [Import.new(WASI, "fd_write", [0x7F, 0x7F, 0x7F, 0x7F], [0x7F]),
                       Import.new(WASI, "proc_exit", [0x7F], [])].freeze #: Array[Import]

        COND = { "eq" => :eq, "ne" => :ne, "slt" => :lt_s, "sle" => :le_s, "sgt" => :gt_s, "sge" => :ge_s,
                 "ult" => :lt_u, "ule" => :le_u, "ugt" => :gt_u, "uge" => :ge_u }.freeze #: Hash[String, Symbol]

        # The runtime part of a module, emitted one time and kept. It contains
        # the function names and signatures, their bodies, the types they use,
        # the placed and patched data, the table, and the symbols that it refers
        # to but a program defines. Those symbols have fixed indices and
        # addresses (`pending`). A program's module puts its own part after
        # this one and must define those symbols at those positions.
        # @rbs skip
        Prelude = Data.define(:imports, :shims, :sigs, :bodies, :types, :data_at, :data_end, :segments, :table,
                              :pending)

        class Prelude
          #: () -> Array[String]
          def functions = sigs.keys
        end

        # `prelude`: a Prelude that this module extends. `pending`: when this
        # emits a prelude, the function and data names that another module
        # defines, in the order that it must define them.
        #: (Array[IR::Function] functions, Array[Obj::Datum] data, ?prelude: Prelude?, ?pending: pending?) -> void
        def initialize(functions, data, prelude: nil, pending: nil)
          @functions = functions
          @data = data
          @prelude = prelude
          @pending = pending
        end

        # Returns a Prelude of these functions and data, for modules to extend.
        # A body reads only the layout, so a block can make the bodies in
        # other processes, or take them from a cache: it gets the functions
        # and this emitter (`body`, `call_types`), and returns the unlinked
        # bodies in the order of the functions.
        #: () ?{ (Array[IR::Function], Codegen) -> Array[Array[String | reference]] } -> Prelude
        def prelude
          layout
          bodies = block_given? ? yield(@functions, self) : @functions.map { |f| body(f) }
          Prelude.new(@imports, @shims, @functions.to_h { |f| [f.name, signature(f)] }, bodies.map { |b| link(b) }, @types,
                      @data_at, @data_end, placed_data, @table, @promised)
        end

        # The unlinked body of `f` (`Body#emit`).
        #: (IR::Function f) -> Array[String | reference]
        def body(f) = Body.new(self, f).emit

        # The wasm type of each function that `f` calls, as its body reads
        # them: a call converts each argument and the result to the callee's
        # type. With `f`'s IR, they decide its body.
        #: (IR::Function f) -> Array[signature?]
        def call_types(f) = f.callees.map { |c| function_type(c.symbol) }

        # The bytes of an unlinked body, with each reference filled in from
        # the layout.
        #: (Array[String | reference] parts) -> String
        def link(parts)
          code = "".b
          parts.each do |part|
            next code << part if part.is_a?(String)

            kind, of = part
            next code << leb(known_type_index(of)) unless of.is_a?(String)

            if kind == :call && (type = @slotted[of])
              # A call to a function that the program defines goes through
              # its table slot, so the prelude's code is the same in a
              # module of its own (`runtime_module`): the `call` byte
              # before the reference becomes `call_indirect`.
              code.chop!
              code << i32c(table_index(of)) << "\x11".b << leb(known_type_index(type)) << "\x00".b
              next
            end

            code << case kind
                    when :call then leb(function_index(of))
                    when :table then sleb(table_index(of))
                    else sleb(data_address(of))
                    end
          end
          vec_bytes(code)
        end

        # `[address, bytes]` of each initialized data object.
        #: () -> Array[[Integer, String]]
        def placed_data
          @data.reject { |d| d.section == :bss }.map do |d|
            [@data_at[d.name], patched(d)] #: [Integer, String]
          end
        end

        # Returns the module's bytes: the whole module, or with `split`, the
        # program's part, which imports the prelude's functions, memory,
        # table and globals from the runtime module (`runtime_module`)
        # under RUNTIME. The imports come in the order of the prelude's
        # functions, so each function keeps the index, and each object
        # the address, that it has in the whole module.
        #: (?split: String?) -> String
        def emit(split: nil)
          layout
          pre = @prelude
          raise Refused, "no _start without a prelude or a main" unless pre || @functions.any? { |f| f.name == "main" }
          raise Refused, "a program module needs the prelude of its runtime module" if split && pre.nil?

          @index["_start"] = @index.size
          own = @functions.map { |f| link(body(f)) }
          sigs = pre ? pre.sigs.values : [] #: Array[signature]
          start = [[], []] #: signature
          own_sigs = @functions.map { |f| signature(f) } + [start]
          shim_sigs = @shims.map { |name| LIBC_SHIMS.fetch(name) }
          (@imports.map(&:signature) + shim_sigs + sigs + own_sigs).each { |t| type_index(t) }
          stack_base = Bytes.align(@data_end, 16)
          heap_base = Bytes.align(stack_base + (STACK_PAGES * PAGE), 16)
          return program_module(split, pre, own, own_sigs, [stack_base, heap_base]) if split && pre

          bodies = @shims.map { |name| shim(name) } + (pre ? pre.bodies : []) + own + [start_body]
          out = MAGIC.dup
          out << type_section << import_section
          out << section(3, vec((shim_sigs + sigs + own_sigs).map { |t| leb(type_index(t)) }))
          out << section(4, vec(["\x70\x00".b + leb(@table.size + 1)])) unless @table.empty?
          out << section(5, vec(["\0".b + leb((heap_base / PAGE) + 2)]))
          out << section(6, globals(stack_base, heap_base))
          out << section(7, vec([name("memory") + "\x02".b + leb(0), name("_start") + "\0".b + leb(@index["_start"])]))
          out << section(9, vec(["\0".b + i32c(1) + "\x0B".b + vec(@table.map { |n| leb(function_index(n)) })])) unless @table.empty?
          out << section(10, vec(bodies))
          placed = pre ? pre.segments : [] #: Array[[Integer, String]]
          placed += placed_data
          out << section(11, vec(segments(placed).map { |at, bytes| "\0".b + "\x41".b + sleb(at) + "\x0B".b + vec_bytes(bytes) }))
          out << names_section if Config.current.wasm_names?
          out
        end

        # The runtime module of a prelude: its imports, shims and functions,
        # at the indices that they have in a whole module, with its data
        # and table entries. It is a reactor: no `_start`, and nothing runs
        # until a program module's `_start` calls in. It exports its memory,
        # its table (with PROGRAM_SLOTS after its own entries), its globals
        # and each function; a program module imports them all.
        #: (?link: String?) -> String
        def runtime_module(link: nil)
          pre = @prelude or raise ArgumentError, "a runtime module is the prelude's"
          @imports = pre.imports
          @shims = pre.shims
          @index = {}
          @imports.each_with_index { |import, i| @index[import.name] = i }
          @shims.each { |name| @index[name] = @index.size }
          pre.functions.each { |name| @index[name] = @index.size }
          @types = pre.types.dup
          @type_at = @types.each_with_index.to_h
          @table = pre.table
          @table_at = @table.each_with_index.to_h { |name, i| [name, i + 1] }
          shim_sigs = @shims.map { |name| LIBC_SHIMS.fetch(name) }
          (@imports.map(&:signature) + shim_sigs + pre.sigs.values).each { |t| type_index(t) }
          stack_base = Bytes.align(pre.data_end, 16)
          heap_base = Bytes.align(stack_base + (STACK_PAGES * PAGE), 16)
          defined = @shims + pre.functions

          out = MAGIC.dup
          out << type_section << import_section
          out << section(3, vec((shim_sigs + pre.sigs.values).map { |t| leb(type_index(t)) }))
          out << section(4, vec(["\x70\x00".b + leb(@table.size + 1 + PROGRAM_SLOTS)]))
          out << section(5, vec(["\0".b + leb((heap_base / PAGE) + 2)]))
          out << section(6, globals(stack_base, heap_base))
          exports = [name("memory") + "\x02".b + leb(0), name("table") + "\x01".b + leb(0)]
          exports += GLOBALS.each_with_index.map { |(global, _), i| name(global) + "\x03".b + leb(i) }
          exports += defined.map { |symbol| name(symbol) + "\0".b + leb(function_index(symbol)) }
          out << section(7, vec(exports))
          # The slots of the functions that a program defines stay empty
          # here; the program module's elements fill them.
          runs = element_runs { |symbol, _| @index.key?(symbol) }
          out << section(9, vec(runs)) unless runs.empty?
          out << section(10, vec(@shims.map { |name| shim(name) } + pre.bodies))
          out << section(11, vec(segments(pre.segments).map { |at, bytes| "\0".b + "\x41".b + sleb(at) + "\x0B".b + vec_bytes(bytes) }))
          out << section(0, name(LINK_SECTION) + link.b) if link
          out << names_section if Config.current.wasm_names?
          out
        end

        # The program module (`emit` with `split`): the runtime's file name
        # `split` goes in its RUNTIME_SECTION. Its data is passive: the
        # imported memory has the runtime's size, so `_start` grows it
        # first, then copies each segment in, sets the stack and heap
        # pointers past the program's data, and calls main.
        # `bases` are the stack's and the heap's.
        # @rbs split: String
        # @rbs pre: Prelude
        # @rbs own: Array[String]
        # @rbs own_sigs: Array[signature]
        # @rbs bases: [Integer, Integer]
        # @rbs return: String
        def program_module(split, pre, own, own_sigs, bases)
          stack_base, heap_base = bases
          imported_sigs = @shims.map { |name| LIBC_SHIMS.fetch(name) } + pre.sigs.values
          limit = pre.table.size + 1 + PROGRAM_SLOTS
          raise Refused, "the program takes #{@table.size - pre.table.size} function addresses, past #{PROGRAM_SLOTS}" if @table.size + 1 > limit

          placed = segments(placed_data)
          imports = @imports.map { |i| name(i.from) + name(i.name) + "\0".b + leb(type_index(i.signature)) }
          imports << (name(RUNTIME) + name("memory") + "\x02".b + "\0".b + leb(1))
          imports << (name(RUNTIME) + name("table") + "\x01".b + "\x70\x00".b + leb(@table.size + 1))
          imports.concat(GLOBALS.map { |global, type| name(RUNTIME) + name(global) + "\x03".b + type.chr + "\x01".b })
          (@shims + pre.functions).each_with_index do |symbol, i|
            imports << (name(RUNTIME) + name(symbol) + "\0".b + leb(type_index(imported_sigs.fetch(i))))
          end
          boundary = @imports.size + @shims.size + pre.functions.size

          out = MAGIC.dup
          out << type_section
          out << section(2, vec(imports))
          out << section(3, vec(own_sigs.map { |t| leb(type_index(t)) }))
          out << section(7, vec([name("memory") + "\x02".b + leb(0), name("_start") + "\0".b + leb(@index["_start"])]))
          # Its own functions, and each entry after the prelude's: an
          # address that the program takes of a runtime function, which
          # the runtime module's table does not have.
          runs = element_runs { |symbol, i| i >= pre.table.size || function_index(symbol) >= boundary }
          out << section(9, vec(runs)) unless runs.empty?
          out << section(12, leb(placed.size))
          out << section(10, vec(own + [start_body(placed: placed, stack_base: stack_base, heap_base: heap_base)]))
          out << section(11, vec(placed.map { |_, bytes| "\x01".b + vec_bytes(bytes) }))
          out << section(0, name(RUNTIME_SECTION) + split.b)
          out
        end

        # The name of the runtime module that the program module `bytes`
        # imports (its RUNTIME_SECTION), or nil for a whole module.
        #: (String bytes) -> String?
        def self.runtime_of(bytes)
          at = 8
          while at < bytes.bytesize
            id = bytes.getbyte(at).to_i
            size, at = read_leb(bytes, at + 1)
            if id.zero?
              length, start = read_leb(bytes, at)
              return bytes.byteslice(start + length, size - (start + length - at)) if bytes.byteslice(start, length) == RUNTIME_SECTION
            end
            at += size
          end
          nil
        end

        # The unsigned LEB128 number at `at` in `bytes`, and the offset after it.
        #: (String bytes, Integer at) -> [Integer, Integer]
        def self.read_leb(bytes, at)
          value = 0
          shift = 0
          loop do
            byte = bytes.getbyte(at) or raise ArgumentError, "a LEB128 number runs past the end"
            at += 1
            value |= (byte & 0x7F) << shift
            return [value, at] if byte < 0x80

            shift += 7
          end
        end

        # The active element segments of the table entries that the block
        # takes (each symbol, with its position in the table): one for each
        # run of them, at its first slot.
        #: () { (String, Integer) -> bool } -> Array[String]
        def element_runs
          runs = [] #: Array[[Integer, Array[String]]]
          @table.each_with_index do |symbol, i|
            next unless yield(symbol, i)

            run = runs.last
            run && run[0] + run[1].size == i + 1 ? run[1] << symbol : runs << [i + 1, [symbol]]
          end
          runs.map { |slot, symbols| "\0".b + i32c(slot) + "\x0B".b + vec(symbols.map { |symbol| leb(function_index(symbol)) }) }
        end

        #: () -> String
        def type_section = section(1, vec(@types.map { |p, r| "\x60".b + vec(p.map(&:chr)) + vec(r.map(&:chr)) }))

        #: () -> String
        def import_section = section(2, vec(@imports.map { |i| name(i.from) + name(i.name) + "\0".b + leb(type_index(i.signature)) }))

        # The globals, in their order (`GLOBALS`): the shadow stack pointer,
        # the heap pointer, and the gate word (`IR::Inst::GATES`).
        #: (Integer stack_base, Integer heap_base) -> String
        def globals(stack_base, heap_base)
          vec(["\x7F\x01".b + "\x41".b + sleb(stack_base) + "\x0B".b,
               "\x7F\x01".b + "\x41".b + sleb(heap_base) + "\x0B".b,
               "\x7E\x01".b + "\x42\x00".b + "\x0B".b])
        end

        # The function names, as a custom section. The program does not read
        # it, but wasmtime does: a trap then shows `zr_ivtab_append` in place
        # of `<wasm function 1097>`. It is as large as all symbol names, so
        # it is emitted only on request.
        #: () -> String
        def names_section
          rows = @index.sort_by(&:last).map { |symbol, index| leb(index) + name(symbol) }
          section(0, name("name") + section(1, vec(rows)))
        end

        # The active data segments for `[address, bytes]` objects: objects
        # closer than SEGMENT_GAP bytes share one segment, with zeros between
        # them.
        #: (Array[[Integer, String]] placed) -> Array[[Integer, String]]
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
        #: () -> void
        def layout
          pre = @prelude
          @imports = pre ? pre.imports : imports
          if pre
            extra = imported.map(&:name) - @imports.map(&:name)
            raise Refused, "the prelude does not import #{extra.join(", ")}" unless extra.empty?
          end
          names = @pending
          pending = names ? names[:functions] : [] #: Array[String]
          @shims = pre ? pre.shims : LIBC_SHIMS.keys - @functions.map(&:name) - pending
          @index = {}
          @imports.each_with_index { |import, i| @index[import.name] = i }
          @shims.each { |name| @index[name] = @index.size }
          pre&.functions&.each { |name| @index[name] = @index.size }
          if pre
            missing = pre.pending[:functions] - @functions.map(&:name)
            raise Refused, "the prelude waits for #{missing.join(", ")}" unless missing.empty?

            first = pre.pending[:functions].each_with_index.to_h
            @functions = @functions.sort_by.with_index { |f, i| [first.fetch(f.name, first.size), i] }
          end
          # Initialized data comes before bss, so the written bytes are one
          # run, not one segment between each pair of zero objects.
          waiting = pre ? pre.pending[:data].keys : [] #: Array[String]
          first = waiting.each_with_index.to_h
          @data = @data.sort_by.with_index { |d, i| [first.fetch(d.name, first.size), d.section == :bss ? 1 : 0, i] }
          @functions.each { |f| @index[f.name] = @index.size }
          @types = pre ? pre.types.dup : []
          @type_at = @types.each_with_index.to_h
          place_data(pre ? pre.data_end : DATA_BASE, pre ? pre.data_at.dup : {})
          pre&.pending&.[](:data)&.each do |name, at|
            raise Refused, "#{name} is at #{@data_at[name].inspect}, not the #{at} the prelude promised" unless @data_at[name] == at
          end

          used = (@functions.flat_map { |f| f.callees.map(&:symbol) } - @index.keys).uniq
          promise
          unknown = used - @shims - @promised[:functions]
          raise Refused, "no wasm shim for #{unknown.join(", ")}" unless unknown.empty?

          taken = [] #: Array[String]
          @functions.each { |f| survey(f, taken) }
          named = @data.flat_map { |d| d.relocs.map(&:symbol) }.select { |name| @index.key?(name) }
          table = pre ? pre.table : [] #: Array[String]
          @table = (table + taken + named + slot_pending).uniq
          # A function address is its table index, from 1, so it is never zero.
          @table_at = @table.each_with_index.to_h { |name, i| [name, i + 1] }
          @import_named = @imports.to_h { |import| [import.name, import] }
        end

        # A prelude calls each function that a program defines through a
        # table slot (`link`), so its code calls no index outside itself.
        # Returns the names, for the table, after it notes the wasm type of
        # each call in `@slotted`.
        #: () -> Array[String]
        def slot_pending
          @slotted = {}
          names = @promised[:functions]
          return names if names.empty?

          wanted = names.to_h { |name| [name, true] }
          @functions.each do |f|
            f.callees.each do |c|
              next unless wanted[c.symbol] && !c.from

              # An address that `f` takes needs no type: only a call does.
              sig = f.sigs.find { |x| x.sig == c.sig } or next
              type = sig_type(sig)
              type_index(type)
              known = @slotted[c.symbol] ||= type
              raise Refused, "#{c.symbol} is called as #{known.inspect} and as #{type.inspect}" unless known == type
            end
          end
          names
        end

        # Adds the symbol of each function address that `f` takes to `taken`,
        # and the type of each of its indirect calls to the type section, in
        # the order that the bodies use them. A body then only reads the
        # layout, so it can be emitted in another process.
        #: (IR::Function f, Array[String] taken) -> void
        def survey(f, taken)
          f.blocks.each do |b|
            b.insts.each do |i|
              case i.op
              when :func_addr
                c = f.callees.find { |x| x.fn == i.args[0] } or raise "#{f.name}: no callee #{i.args[0]}"
                taken << c.symbol
              when :call_indirect
                sig = f.sigs.find { |x| x.sig == i.callee } or raise "#{f.name}: no signature #{i.callee}"
                type_index(sig_type(sig))
              end
            end
          end
        end

        # The module's own imports, then each import that its functions
        # refer to, in order of first use.
        #: () -> Array[Import]
        def imports
          by_name = {} #: Hash[String, Import]
          (OWN_IMPORTS + imported).each do |import|
            known = by_name[import.name] ||= import
            raise Refused, "#{import.name} is imported as #{known.to_h.inspect} and #{import.to_h.inspect}" unless known == import
          end
          by_name.values
        end

        # The imports of the functions, with types from the IR signature of each call.
        #: () -> Array[Import]
        def imported
          @functions.flat_map do |f|
            f.callees.filter_map do |c|
              from = c.from or next
              sig = f.sigs.find { |s| s.sig == c.sig } or raise "#{f.name}: no signature #{c.sig}"
              params, results = sig_type(sig)
              Import.new(from, c.symbol, params, results)
            end
          end
        end

        # When this emits a prelude, the pending functions get the indices
        # directly after this module's functions. The pending data gets the
        # addresses directly after this module's data, 8 bytes each, except
        # the last, which can be any size.
        #: () -> void
        def promise
          @promised = { functions: [], data: {} }
          pending = @pending
          return unless pending

          pending[:functions].each { |name| @index[name] = @index.size }
          @promised[:functions] = pending[:functions]
          at = @data_end
          pending[:data].each do |name|
            at = Bytes.align(at, 8)
            @promised[:data][name] = at
            @data_at[name] = at
            at += 8
          end
        end

        #: (IR::Function f) -> signature
        def signature(f)
          [f.params.map { |t| TYPE.fetch(t.split.first) }, f.ret_type ? [TYPE.fetch(f.ret_type)] : []]
        end

        #: (signature t) -> Integer
        def type_index(t)
          @type_at[t] ||= (@types << t).size - 1
        end

        # The index of a type that `layout` added (`survey`).
        #: (signature t) -> Integer
        def known_type_index(t)
          @type_at.fetch(t) { raise "#{t.inspect} is not in the type section" }
        end

        #: (String name) -> Integer
        def function_index(name)
          @index.fetch(name) { raise Refused, "no function named #{name}" }
        end

        # Returns the wasm parameter and result types for a call to `name`,
        # or nil for a function that this module does not know.
        #: (String name) -> signature?
        def function_type(name)
          return LIBC_SHIMS[name] if @shims.include?(name)
          pre = @prelude
          return pre.sigs[name] if pre&.sigs&.key?(name)

          named = @function_named ||= @functions.to_h { |x| [x.name, x] }
          f = named[name]
          return signature(f) if f

          @import_named[name]&.signature
        end

        # The table index that represents the address of `name`.
        #: (String name) -> Integer
        def table_index(name)
          @table_at.fetch(name) { raise "#{name} is not in the table" }
        end

        # The wasm type of an IR signature.
        #: (IR::Sig s) -> signature
        def sig_type(s)
          [s.params.map { |t| TYPE.fetch(t) }, s.ret ? [TYPE.fetch(s.ret)] : []]
        end

        # Returns a data object's bytes with every absolute relocation filled
        # in. A function's address is its table index, as for `func_addr`.
        #: (Obj::Datum d) -> String
        def patched(d)
          bytes = d.bytes.dup
          d.relocs.each do |r|
            raise Refused, "#{d.name}: a #{r.kind} relocation in data" unless r.kind == :abs64

            address = @index.key?(r.symbol) ? table_index(r.symbol) : data_address(r.symbol)
            bytes[r.offset, 8] = [address + r.addend].pack("Q<")
          end
          bytes
        end

        #: (String name) -> Integer
        def data_address(name)
          @data_at.fetch(name) { raise Refused, "no data named #{name}" }
        end

        #: (Integer at, Hash[String, Integer] placed) -> void
        def place_data(at, placed)
          @data_at = placed
          @data.each do |d|
            at = Bytes.align(at, [d.align, 1].max)
            @data_at[d.name] = at
            at += d.size
          end
          @data_end = at
        end

        # `_start`: main(0, 0), then proc_exit with its return value. A
        # program module's first puts its data in place (`program_module`).
        #: (?placed: Array[[Integer, String]]?, ?stack_base: Integer, ?heap_base: Integer) -> String
        def start_body(placed: nil, stack_base: 0, heap_base: 0)
          type = function_type("main") or raise Refused, "no main"
          params, results = type
          code = +"".b
          if placed
            need = (heap_base / PAGE) + 2
            # memory.size < need: memory.grow(need - memory.size).
            code << i32c(need) << "\x3F\x00".b << "\x4B".b << "\x04\x40".b
            code << i32c(need) << "\x3F\x00".b << "\x6B".b << "\x40\x00".b << "\x1A".b << "\x0B".b
            placed.each_with_index do |(at, bytes), k|
              code << i32c(at) << i32c(0) << i32c(bytes.bytesize) << "\xFC\x08".b << leb(k) << "\x00".b
              code << "\xFC\x09".b << leb(k)
            end
            code << i32c(stack_base) << "\x24\x00".b << i32c(heap_base) << "\x24\x01".b
          end
          params.each { |t| code << (t == 0x7E ? "\x42\x00".b : "\x41\x00".b) }
          code << "\x10".b << leb(function_index("main"))
          code << (results.first == 0x7E ? "\xA7".b : "".b) unless results.empty?
          code << (results.empty? ? i32c(0) : "".b)
          code << "\x10".b << leb(function_index("proc_exit")) << "\x0B".b
          vec_bytes(vec([]) + code)
        end

        # --- encoding ---------------------------------------------------

        #: (Integer n) -> String
        def leb(n) = Bytes.leb(n)

        #: (Integer n) -> String
        def sleb(n) = Bytes.sleb(n)

        #: (Integer n) -> String
        def i32c(n)
          "\x41".b + sleb(n)
        end

        #: (Array[String] items) -> String
        def vec(items)
          leb(items.size) + items.join
        end

        #: (String bytes) -> String
        def vec_bytes(bytes)
          leb(bytes.bytesize) + bytes
        end

        #: (String s) -> String
        def name(s)
          vec_bytes(s.b)
        end

        #: (Integer id, String payload) -> String
        def section(id, payload)
          id.chr + vec_bytes(payload)
        end
      end
    end
  end
end
