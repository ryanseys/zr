# frozen_string_literal: true

require_relative "function"
require_relative "../obj/model"

module Ze0
  module IR
    # The wasm32 emitter: IR functions and data objects to one WASI module.
    #
    # Every value is a local of its type (an i8 is an i32 local; an i64
    # stays i64, so a pointer is a 64-bit value whose address wraps to 32
    # bits at every memory access). Control flow is one `loop` around a
    # ladder of `block`s and a `br_table` on a block-index local: each IR
    # block sets the index of its successor and branches to the loop.
    # Stack slots live in a shadow stack in linear memory under a global
    # stack pointer. `write` and `exit` are the two libSystem calls the
    # programs make, and become `fd_write` and `proc_exit` shims; `malloc`
    # bumps a heap pointer above the shadow stack and grows the memory,
    # `free` does nothing, and the environment and working directory
    # calls find nothing. A
    # function's address is its index in the one table, from 1 so that a
    # pointer is never zero; `call_indirect` goes through that table.
    class Wasm
      class Refused < StandardError; end

      PAGE = 65_536
      # The bottom of linear memory: the iovec scratch, WASI's filestat
      # and the errno word, then data objects, then the shadow stack
      # growing up from its base.
      SCRATCH = 16
      FILESTAT = 32
      FDSTAT = 96
      ERRNO = 120
      DATA_BASE = 128
      STACK_PAGES = 16

      TYPE = { "i8" => 0x7F, "i32" => 0x7F, "i64" => 0x7E, "f64" => 0x7C }.freeze
      OP = {
        "i32" => { const: 0x41, add: 0x6A, sub: 0x6B, mul: 0x6C, div_s: 0x6D, div_u: 0x6E, rem_s: 0x6F, rem_u: 0x70,
                   and: 0x71, or: 0x72, xor: 0x73, shl: 0x74, shr_s: 0x75, shr_u: 0x76,
                   eq: 0x46, ne: 0x47, lt_s: 0x48, lt_u: 0x49, gt_s: 0x4A, gt_u: 0x4B, le_s: 0x4C, le_u: 0x4D, ge_s: 0x4E, ge_u: 0x4F },
        "i64" => { const: 0x42, add: 0x7C, sub: 0x7D, mul: 0x7E, div_s: 0x7F, div_u: 0x80, rem_s: 0x81, rem_u: 0x82,
                   and: 0x83, or: 0x84, xor: 0x85, shl: 0x86, shr_s: 0x87, shr_u: 0x88,
                   eq: 0x51, ne: 0x52, lt_s: 0x53, lt_u: 0x54, gt_s: 0x55, gt_u: 0x56, le_s: 0x57, le_u: 0x58, ge_s: 0x59, ge_u: 0x5A }
      }.freeze
      # The libSystem calls the module answers itself.
      SHIMS = { "write" => [[0x7F, 0x7E, 0x7E], [0x7E]], "exit" => [[0x7F], []], "_exit" => [[0x7F], []], "abort" => [[], []],
                "malloc" => [[0x7E], [0x7E]], "free" => [[0x7E], []], "getenv" => [[0x7E], [0x7E]],
                "memmove" => [[0x7E, 0x7E, 0x7E], [0x7E]], "memset" => [[0x7E, 0x7F, 0x7E], [0x7E]],
                "pthread_self" => [[], [0x7E]], "pthread_get_stackaddr_np" => [[0x7E], [0x7E]], "pthread_get_stacksize_np" => [[0x7E], [0x7E]],
                "setenv" => [[0x7E, 0x7E, 0x7F], [0x7F]], "unsetenv" => [[0x7E], [0x7F]], "_NSGetEnviron" => [[], [0x7E]], "getcwd" => [[0x7E, 0x7E], [0x7E]], "getpid" => [[], [0x7F]], "arc4random" => [[], [0x7F]], "access" => [[0x7E, 0x7F], [0x7F]], "stat" => [[0x7E, 0x7E], [0x7F]],
                "mmap" => [[0x7E, 0x7E, 0x7F, 0x7F, 0x7F, 0x7E], [0x7E]], "munmap" => [[0x7E, 0x7E], [0x7F]],
                "mprotect" => [[0x7E, 0x7E, 0x7F], [0x7F]], "posix_memalign" => [[0x7E, 0x7E, 0x7E], [0x7F]],
                "fstat" => [[0x7F, 0x7E], [0x7F]], "__error" => [[], [0x7E]],
                "fcntl" => [[0x7F, 0x7F], [0x7F]], "__fcntl" => [[0x7F, 0x7F, 0x7E], [0x7F]],
                "close" => [[0x7F], [0x7F]], "fsync" => [[0x7F], [0x7F]], "isatty" => [[0x7F], [0x7F]],
                "read" => [[0x7F, 0x7E, 0x7E], [0x7E]], "lseek" => [[0x7F, 0x7E, 0x7F], [0x7E]],
                "clock_gettime" => [[0x7F, 0x7E], [0x7F]],
                "getuid" => [[], [0x7F]], "geteuid" => [[], [0x7F]], "getgid" => [[], [0x7F]],
                "getegid" => [[], [0x7F]], "getppid" => [[], [0x7F]], "umask" => [[0x7F], [0x7F]],
                "sigaction" => [[0x7F, 0x7E, 0x7E], [0x7F]],
                "onig_initialize" => [[0x7E, 0x7F], [0x7F]], "onig_free" => [[0x7E], []],
                "onig_new" => [[0x7E, 0x7E, 0x7E, 0x7F, 0x7E, 0x7E, 0x7E], [0x7F]], "onig_ze0_take_warnings" => [[0x7E, 0x7F], [0x7F]] }.freeze

      # How many i32 locals a shim body declares.
      LOCALS = { "malloc" => 1, "fstat" => 3, "fcntl" => 1, "isatty" => 1, "read" => 1, "lseek" => 1 }.freeze

      # WASI names eight file types; macOS names them in `st_mode`, and
      # carries permission bits WASI does not have. The bits below are
      # what a fresh file, directory or terminal usually carries, which
      # is the closest a module without them can answer.
      FILETYPE = { 0 => 0, 1 => 0o060644, 2 => 0o020666, 3 => 0o040755,
                   4 => 0o100644, 5 => 0o140644, 6 => 0o140644, 7 => 0o120777 }.freeze

      COND = { "eq" => :eq, "ne" => :ne, "slt" => :lt_s, "sle" => :le_s, "sgt" => :gt_s, "sge" => :ge_s,
               "ult" => :lt_u, "ule" => :le_u, "ugt" => :gt_u, "uge" => :ge_u }.freeze

      # The runtime's half of a module, emitted once and kept: its
      # function names and signatures, their bodies, the types they use,
      # its data placed and patched, its table, and the symbols it names
      # that a program defines, at the indices and addresses promised to
      # its bodies. A program's module lays its own part after this one
      # and must honour the promises (`pending`).
      Prelude = Struct.new(:sigs, :bodies, :types, :data_at, :data_end, :segments, :table, :pending) do
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
        Prelude.new(@functions.to_h { |f| [f.name, signature(f)] }, bodies, @types, @data_at, @data_end,
                    @data.reject { |d| d.section == :bss }.map { |d| [@data_at[d.name], patched(d)] }, @table, @promised)
      end

      # The module's bytes.
      def emit
        layout
        pre = @prelude
        raise Refused, "no _start without a prelude or a main" unless pre || @functions.any? { |f| f.name == "main" }

        @index["_start"] = @index.size
        own = @functions.map { |f| Body.new(self, f).emit }
        bodies = @shims.map { |name, _| shim(name) } + (pre ? pre.bodies : []) + own + [start_body]
        sigs = (pre ? pre.sigs.values : []) + @functions.map { |f| signature(f) } + [[[], []]]
        (@imports.map { |(_, _, p, r)| [p, r] } + @shims.values + sigs).each { |t| type_index(t) }

        out = +"\0asm\x01\0\0\0".b
        out << section(1, vec(@types.map { |p, r| "\x60".b + vec(p.map(&:chr)) + vec(r.map(&:chr)) }))
        out << section(2, vec(@imports.map { |(mod, name, p, r)| name(mod) + name(name) + "\0".b + leb(type_index([p, r])) }))
        out << section(3, vec((@shims.values + sigs).map { |t| leb(type_index(t)) }))
        out << section(4, vec(["\x70\x00".b + leb(@table.size + 1)])) unless @table.empty?
        stack_base = align(@data_end, 16)
        heap_base = align(stack_base + (STACK_PAGES * PAGE), 16)
        out << section(5, vec(["\0".b + leb((heap_base / PAGE) + 2)]))
        out << section(6, vec(["\x7F\x01".b + "\x41".b + sleb(stack_base) + "\x0B".b,
                               "\x7F\x01".b + "\x41".b + sleb(heap_base) + "\x0B".b]))
        out << section(7, vec([name("memory") + "\x02".b + leb(0), name("_start") + "\0".b + leb(@index["_start"])]))
        out << section(9, vec(["\0".b + i32c(1) + "\x0B".b + vec(@table.map { |n| leb(function_index(n)) })])) unless @table.empty?
        out << section(10, vec(bodies))
        segments = (pre ? pre.segments : []) + @data.reject { |d| d.section == :bss }.map { |d| [@data_at[d.name], patched(d)] }
        out << section(11, vec(segments.map { |at, bytes| "\0".b + "\x41".b + sleb(at) + "\x0B".b + vec_bytes(bytes) }))
        out
      end

      # Function index space: imports first, then the shims, then the
      # prelude's functions, then ours (the prelude's pending ones first,
      # where it promised them). Data after the prelude's, the pending
      # objects first, at the addresses promised. Types and the table
      # continue the prelude's.
      def layout
        pre = @prelude
        @imports = [["wasi_snapshot_preview1", "fd_write", [0x7F, 0x7F, 0x7F, 0x7F], [0x7F]],
                    ["wasi_snapshot_preview1", "proc_exit", [0x7F], []],
                    ["wasi_snapshot_preview1", "fd_filestat_get", [0x7F, 0x7F], [0x7F]],
                    ["wasi_snapshot_preview1", "fd_fdstat_get", [0x7F, 0x7F], [0x7F]],
                    ["wasi_snapshot_preview1", "fd_close", [0x7F], [0x7F]],
                    ["wasi_snapshot_preview1", "fd_sync", [0x7F], [0x7F]],
                    ["wasi_snapshot_preview1", "fd_read", [0x7F, 0x7F, 0x7F, 0x7F], [0x7F]],
                    ["wasi_snapshot_preview1", "fd_seek", [0x7F, 0x7E, 0x7F, 0x7F], [0x7F]],
                    ["wasi_snapshot_preview1", "clock_time_get", [0x7F, 0x7E, 0x7F], [0x7F]],
                    ["wasi_snapshot_preview1", "random_get", [0x7F, 0x7F], [0x7F]]]
        @shims = SHIMS
        @index = {}
        @imports.each_with_index { |(_, name, *), i| @index[name] = i }
        @shims.each_key { |name| @index[name] = @index.size }
        pre&.functions&.each { |name| @index[name] = @index.size }
        if pre
          missing = pre.pending[:functions] - @functions.map(&:name)
          raise Refused, "the prelude waits for #{missing.join(", ")}" unless missing.empty?

          first = pre.pending[:functions]
          @functions = @functions.sort_by.with_index { |f, i| [first.index(f.name) || first.size, i] }
          first = pre.pending[:data].keys
          @data = @data.sort_by.with_index { |d, i| [first.index(d.name) || first.size, i] }
        end
        @functions.each { |f| @index[f.name] = @index.size }
        @types = pre ? pre.types.dup : []
        place_data(pre ? pre.data_end : DATA_BASE, pre ? pre.data_at.dup : {})
        pre&.pending&.[](:data)&.each do |name, at|
          raise Refused, "#{name} is at #{@data_at[name].inspect}, not the #{at} the prelude promised" unless @data_at[name] == at
        end

        used = (@functions.flat_map { |f| f.callees.map(&:symbol) } - @index.keys).uniq
        promise(used)
        unknown = used - @shims.keys - @promised[:functions]
        raise Refused, "no wasm shim for #{unknown.join(", ")}" unless unknown.empty?

        taken = @functions.flat_map { |f| f.blocks.flat_map(&:insts).select { |i| i.op == :func_addr }.map { |i| f.callees.find { |c| c.fn == i.args[0] }.symbol } }
        named = @data.flat_map { |d| d.relocs.map(&:symbol) }.select { |name| @index.key?(name) }
        @table = ((pre ? pre.table : []) + taken + named).uniq
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

      # The wasm parameter and result types a call to `name` must match.
      # The wasm parameter and result types a call to `name` must match;
      # nil for a function this module has not seen.
      def function_type(name)
        return @shims[name] if @shims.key?(name)
        return @prelude.sigs[name] if @prelude&.sigs&.key?(name)

        @function_named ||= @functions.to_h { |x| [x.name, x] }
        f = @function_named[name]
        return signature(f) if f

        @imports.find { |(_, n, *)| n == name }&.[](2..3)
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
        when "getenv", "pthread_self", "pthread_get_stackaddr_np", "pthread_get_stacksize_np", "_NSGetEnviron", "mmap"
          code << "\x42\x00".b
        # mprotect succeeds and does nothing: WASI has no PROT_NONE, and
        # CRuby sets no guard page there either.
        when "setenv", "unsetenv", "getpid", "mprotect"
          code << "\x41\x00".b
        # A module is given no working directory, and the root is the
        # one path every host agrees exists.
        when "getcwd"
          code << "\x20\x00".b << "\xA7".b << i32c(0x2F) << "\x3A\x00".b << leb(0)
          code << "\x20\x00".b << "\xA7".b << i32c(0) << "\x3A\x00".b << leb(1)
          code << "\x20\x00".b
        # Four bytes from the host. A constant would make every Random
        # the same one, which is the opposite of what the call is for.
        when "arc4random"
          code << call_wasi("random_get", [i32c(SCRATCH), i32c(4)]) << "\x1A".b
          code << i32c(SCRATCH) << "\x28\x02".b << leb(0)
        when "munmap"
          code << "\x41\x7F".b
        # A module has no path metadata, so a path is not found. The
        # errno is set rather than left over: the caller reads it next.
        when "access", "stat"
          code << errno(2) << "\x41\x7F".b
        when "__error"
          code << "\x42".b << sleb(ERRNO)
        when "getuid", "geteuid", "getgid", "getegid"
          code << i32c(0)
        # The regex engine is C, and a module carries none. The runtime
        # readies it, and the core library compiles a pattern of its
        # own, before a program has said whether it wants one: so
        # readying succeeds, and compiling answers a handle that stands
        # for a pattern nothing can match. A program that matches one
        # stops at `onig_search`, which names what is missing. Nothing it
        # compiles gives a warning.
        when "onig_initialize", "onig_free", "onig_ze0_take_warnings"
          code << (SHIMS.fetch(name).last.empty? ? "".b : i32c(0))
        when "onig_new"
          code << "\x20\x00".b << "\xA7".b << "\x42\x01".b << "\x37\x03".b << leb(0) << i32c(0)
        # A module takes no signals, so each one keeps the handler it
        # started with, the default, and a new one changes nothing.
        when "sigaction"
          code << "\x20\x02\x42\x00\x52\x04\x40".b
          code << "\x20\x02\xA7\x42\x00".b << "\x37\x03\x00".b
          code << "\x0B".b << i32c(0)
        when "getppid"
          code << i32c(1)
        # The process mask a fresh login shell carries. A module has no
        # mask of its own and nothing it creates is shared, so the value
        # only has to be the one a program reads back.
        when "umask"
          code << i32c(0o022)
        # Setting a descriptor's flags does nothing: WASI has no
        # close-on-exec, and a module that cannot spawn never execs.
        when "__fcntl"
          code << i32c(0)
        when "close"
          code << status(call_wasi("fd_close", ["\x20\x00".b]))
        when "fsync"
          code << status(call_wasi("fd_sync", ["\x20\x00".b]))
        when "fstat"
          code << fstat_body
        when "fcntl"
          code << fcntl_body
        when "isatty"
          code << isatty_body
        when "read"
          code << read_body
        when "lseek"
          code << lseek_body
        when "clock_gettime"
          code << clock_body
        end
        code << "\x0B".b
        n = LOCALS[name]
        vec_bytes(vec(n ? [leb(n) + "\x7F".b] : []) + code)
      end

      # `errno = n`, and nothing left on the stack.
      def errno(n) = i32c(ERRNO) + i32c(n) + "\x36\x02".b + leb(0)

      def call_wasi(name, args) = args.join + "\x10".b + leb(function_index(name))

      # A WASI call that answers nothing but an errno, as the libSystem
      # call it stands for answers 0 or -1 and leaves the reason behind.
      def status(call)
        i32c(ERRNO) + call + "\x36\x02".b + leb(0) +
          i32c(-1) + i32c(0) + i32c(ERRNO) + "\x28\x02".b + leb(0) + "\x1B".b
      end

      # `errno = local n; answer`, for the failure arm of a shim that
      # has an answer of its own to give.
      def failed(local, answer)
        i32c(ERRNO) + "\x20".b + leb(local) + "\x36\x02".b + leb(0) + answer + "\x0F".b
      end

      # F_GETFL alone: the flags say what the descriptor was opened for,
      # which WASI keeps as rights rather than as a mode. Every other
      # command answers 0, since a module has nothing they would change.
      # Local 2 is the errno.
      def fcntl_body
        rights = i32c(FDSTAT) + "\x29\x03".b + leb(8)
        readable = rights + "\x42".b + sleb(2) + "\x83".b + "\x42\x00".b + "\x52".b
        writable = rights + "\x42".b + sleb(64) + "\x83".b + "\x42\x00".b + "\x52".b
        flags = i32c(FDSTAT) + "\x2F\x01".b + leb(2)
        code = +"".b
        code << "\x20\x01".b << i32c(3) << "\x47".b << "\x04\x40".b << i32c(0) << "\x0F".b << "\x0B".b
        code << call_wasi("fd_fdstat_get", ["\x20\x00".b, i32c(FDSTAT)]) << "\x22\x02".b
        code << "\x04\x40".b << failed(2, i32c(-1)) << "\x0B".b
        code << i32c(2) << i32c(1) << readable << "\x1B".b << i32c(0) << writable << "\x1B".b
        # O_APPEND is 8 on this platform and 1 in WASI; O_NONBLOCK is 4
        # in both, so it needs no move.
        code << i32c(8) << i32c(0) << (flags + i32c(1) + "\x71".b) << "\x1B".b << "\x72".b
        code << (flags + i32c(4) + "\x71".b) << "\x72".b
        code
      end

      # A terminal is a character device. Local 1 is the errno.
      def isatty_body
        code = +"".b
        code << call_wasi("fd_fdstat_get", ["\x20\x00".b, i32c(FDSTAT)]) << "\x22\x01".b
        code << "\x04\x40".b << failed(1, i32c(0)) << "\x0B".b
        code << i32c(FDSTAT) << "\x2D\x00".b << leb(0) << i32c(2) << "\x46".b
        code
      end

      # read(2) as one iovec. Local 3 is the errno.
      def read_body
        code = +"".b
        code << i32c(SCRATCH) << "\x20\x01".b << "\xA7".b << "\x36\x02".b << leb(0)
        code << i32c(SCRATCH) << "\x20\x02".b << "\xA7".b << "\x36\x02".b << leb(4)
        code << call_wasi("fd_read", ["\x20\x00".b, i32c(SCRATCH), i32c(1), i32c(SCRATCH + 8)])
        code << "\x22\x03".b << "\x04\x40".b << failed(3, "\x42\x7F".b) << "\x0B".b
        code << i32c(SCRATCH + 8) << "\x28\x02".b << leb(0) << "\xAD".b
        code
      end

      # lseek(2). SEEK_SET, SEEK_CUR and SEEK_END are 0, 1 and 2 in both
      # this platform and WASI. Local 3 is the errno.
      def lseek_body
        code = +"".b
        code << call_wasi("fd_seek", ["\x20\x00".b, "\x20\x01".b, "\x20\x02".b, i32c(SCRATCH)])
        code << "\x22\x03".b << "\x04\x40".b << failed(3, "\x42\x7F".b) << "\x0B".b
        code << i32c(SCRATCH) << "\x29\x03".b << leb(0)
        code
      end

      # clock_gettime(2) into a timespec. WASI counts nanoseconds in one
      # word and numbers its clocks differently: 0 is the wall clock in
      # both, and everything else here is the monotonic one.
      def clock_body
        nanos = i32c(SCRATCH) + "\x29\x03".b + leb(0) + "\x42".b + sleb(1_000_000_000)
        into = "\x20\x01".b + "\xA7".b
        code = +"".b
        code << i32c(ERRNO)
        code << call_wasi("clock_time_get", [i32c(0) + i32c(1) + "\x20\x00".b + "\x45".b + "\x1B".b,
                                             "\x42".b + sleb(1000), i32c(SCRATCH)])
        code << "\x36\x02".b << leb(0)
        code << i32c(ERRNO) << "\x28\x02".b << leb(0) << "\x04\x40".b << i32c(-1) << "\x0F".b << "\x0B".b
        code << into << (nanos + "\x80".b) << "\x37\x03".b << leb(0)
        code << into << (nanos + "\x82".b) << "\x37\x03".b << leb(8)
        code << i32c(0)
        code
      end

      # fstat(2) over WASI's `fd_filestat_get`, which answers eight
      # fields where macOS's `struct stat` has twenty. What WASI knows
      # is copied across; an owner is root and a device is zero, because
      # a module is told neither. Locals: 2 the buffer, 3 the errno, 4
      # the file type.
      def fstat_body
        code = +"".b
        code << "\x20\x01".b << "\xA7".b << "\x21\x02".b
        code << "\x20\x00".b << i32c(FILESTAT) << "\x10".b << leb(function_index("fd_filestat_get"))
        code << "\x22\x03".b << "\x04\x40".b
        code << i32c(ERRNO) << "\x20\x03".b << "\x36\x02".b << leb(0)
        code << "\x41\x7F".b << "\x0F".b << "\x0B".b
        code << i32c(FILESTAT) << "\x2D\x00".b << leb(16) << "\x21\x04".b
        code << store32(0, filestat64(0) + "\xA7".b)
        code << store32(4, mode_bits + (filestat64(24) + "\xA7".b + i32c(0xFFFF) + "\x71".b + i32c(16) + "\x74".b) + "\x72".b)
        code << store64(8, filestat64(8))
        [16, 20, 24].each { |at| code << store32(at, i32c(0)) }
        # A timespec is seconds and nanoseconds; WASI counts nanoseconds
        # from the epoch in one word.
        { 32 => 40, 48 => 48, 64 => 56 }.each do |at, from|
          nanos = filestat64(from) + "\x42".b + sleb(1_000_000_000)
          code << store64(at, nanos + "\x80".b)
          code << store64(at + 8, nanos + "\x82".b)
        end
        code << store64(96, filestat64(32))
        code << store64(104, filestat64(32) + "\x42".b + sleb(511) + "\x7C".b + "\x42".b + sleb(512) + "\x80".b)
        code << store32(112, i32c(4096))
        code << i32c(0)
        code
      end

      # `st_mode`'s type bits, chosen by the file type in local 4.
      def mode_bits
        FILETYPE.inject(i32c(FILETYPE.fetch(4))) do |otherwise, (type, mode)|
          i32c(mode) + otherwise + "\x20\x04".b + i32c(type) + "\x46".b + "\x1B".b
        end
      end

      def filestat64(at) = i32c(FILESTAT) + "\x29\x03".b + leb(at)
      def store32(at, value) = "\x20\x02".b + value + "\x36\x02".b + leb(at)
      def store64(at, value) = "\x20\x02".b + value + "\x37\x03".b + leb(at)

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

        # Parameters first, then every value, then the block index and the
        # frame base.
        def assign
          n = 0
          @f.blocks.each { |b| b.params.each { |v, t| @type[v] = t } }
          @f.blocks.first.params.each { |v, _| @local[v] = n; n += 1 }
          @locals = []
          @f.blocks.each_with_index do |b, bi|
            b.params.each do |v, t|
              next if bi.zero?

              @local[v] = n + @locals.size
              @locals << Wasm::TYPE.fetch(t)
            end
            b.insts.each do |i|
              i.results.each_with_index do |v, k|
                @type[v] = result_type(i, k)
                @local[v] = n + @locals.size
                @locals << Wasm::TYPE.fetch(@type[v])
              end
            end
          end
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
          when *Inst::FBINOPS, *Inst::FUNOPS then "f64"
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

        def ops(v)
          Wasm::OP.fetch(wide?(v) ? "i64" : "i32")
        end

        def get(v)
          @code << "\x20".b << @m.leb(@local.fetch(v))
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
          when :iconst
            # A constant written unsigned wraps to its signed bits.
            n = i.args[0]
            n -= 1 << 64 if i.type == "i64" && n >= 1 << 63
            n -= 1 << 32 if i.type != "i64" && n >= 1 << 31
            @code << (i.type == "i64" ? "\x42".b : "\x41".b) << @m.sleb(n)
            set(i.results[0])
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
          when :stack_addr
            @code << "\x20".b << @m.leb(@fp) << @m.i32c(@slot_at[Integer(i.args[0].delete_prefix("ss"))]) << "\x6A".b << "\xAD".b
            set(i.results[0])
          when :symbol_value
            g = global(i.args[0])
            @code << "\x42".b << @m.sleb(@m.data_address(g.symbol))
            set(i.results[0])
          when :func_addr
            @code << "\x42".b << @m.sleb(@m.table_index(callee(i.args[0]).symbol))
            set(i.results[0])
          when :call_indirect
            ptr, *args = i.args
            args.each { |a| get(a) }
            get(ptr)
            @code << "\xA7".b
            @code << "\x11".b << @m.leb(@m.type_index(@m.sig_type(sig_named(i.callee)))) << "\x00".b
            set(i.results[0]) unless i.results.empty?
          when :call
            # A libSystem call's text signature may say i64 where the shim
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
            @code << ops(i.args[0]).fetch(Wasm::COND.fetch(i.cond)).chr
            set(i.results[0])
          when :fcmp
            get(i.args[0])
            get(i.args[1])
            @code << { "eq" => 0x61, "ne" => 0x62, "lt" => 0x63, "gt" => 0x64, "le" => 0x65, "ge" => 0x66 }.fetch(i.cond).chr
            set(i.results[0])
          when *Inst::FBINOPS
            get(i.args[0])
            get(i.args[1])
            @code << { fadd: 0xA0, fsub: 0xA1, fmul: 0xA2, fdiv: 0xA3 }.fetch(i.op).chr
            set(i.results[0])
          when *Inst::FUNOPS
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
          when :iadd, :isub, :imul, :udiv, :sdiv, :urem, :srem, :band, :bor, :bxor, :ishl, :ushr, :sshr
            get(i.args[0])
            get(i.args[1])
            @code << ops(i.args[0]).fetch({ iadd: :add, isub: :sub, imul: :mul, udiv: :div_u, sdiv: :div_s, urem: :rem_u, srem: :rem_s,
                                            band: :and, bor: :or, bxor: :xor, ishl: :shl, ushr: :shr_u, sshr: :shr_s }[i.op]).chr
            set(i.results[0])
          when :select
            get(i.args[1])
            get(i.args[2])
            get(i.args[0])
            @code << "\xAD".b if wide?(i.args[0])
            @code << "\xAC".b if wide?(i.args[0])
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
