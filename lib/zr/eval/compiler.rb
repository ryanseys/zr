# frozen_string_literal: true

# The runtime's own libraries (lib/zr/runtime/lib/zr) call `Primitive`, so they
# run only inside a zr binary. Under ruby, nothing loads this file.
require_relative "../eval"
require_relative "../runtime/lib/zr/eval/arguments"
require_relative "../runtime/lib/zr/eval/forms"
require_relative "../ir/passes"

module Zr
  class Eval
    # A string of ruby, compiled at run time in the program that evals it.
    # prism parses it, the same lowering as the program's turns it into
    # machine code, and the loader writes that code into this process.
    #
    # The program includes the kernel description, and the symbol table
    # starts from the program's own table. So an eval uses the same kernel
    # and the same symbol ids as the code around it.
    class Compiler < Eval
      # @rbs @runtime: Runtime
      # @rbs @description: Machine::Description
      # @rbs @symbols: Machine::Symbols
      # @rbs @syscalls: Obj::JIT::_Syscalls
      # @rbs @aliases: ^(Symbol) -> Symbol?
      # @rbs @count: Integer
      # @rbs @compiled: Hash[Array[untyped], [Integer, Integer, Integer, Integer, Array[Integer], Integer?] | Exception]
      # @rbs @files: Hash[[String, String], [Integer, String?]]
      # @rbs @fixed: Hash[String?, Integer]?
      # @rbs @loaded: Cache::Loaded?

      # The machine of this process: the backend that compiles an eval,
      # and the code that the JIT loader places. A binary bakes
      # RUBY_PLATFORM from its target.
      ARCH = RUBY_PLATFORM.start_with?("x86_64") ? :x86_64 : :aarch64 #: Symbol

      # The compiler loads at the first eval (`Eval.current`). Loading it
      # makes about 100,000 objects, and about 90,000 stay live for the rest
      # of the run.
      #: () -> Compiler
      def self.start
        require_relative "../hir"
        require_relative "../lower"
        require_relative "../backend/aarch64"
        require_relative "../backend/x86_64"
        require_relative "../obj/jit"
        require_relative "../runtime/lib/zr/obj/jit/runtime"
        require_relative "../symbol_numbering"
        require_relative "../cache/loaded"
        require "zr_description"
        new(Runtime.new)
      end

      #: (Runtime runtime) -> void
      def initialize(runtime)
        super()
        @runtime = runtime
        @description = Machine::Description.parse(Machine::Description::KERNEL)
        names = runtime.symbol_names
        @symbols = Machine::Symbols.new(names, sites: runtime.sites, intern: runtime.method(:intern))
        # A file compiled at run time has the kernel's ids in its code, and
        # pool words for the other names (`compile_file`).
        kernel = @description.kernel_names
        @fixed = (names.first(kernel).each_with_index.to_h if kernel) #: Hash[String?, Integer]?
        @syscalls = Obj::JIT::Runtime.new
        @aliases = ->(name) { runtime.alias_of(name) }
        @count = 0
        @compiled = {}
        @files = {}
      end

      # Compiles `source`. Returns the toplevel's address, its FrameMeta
      # (the call writes the calling frame into it), and the shape of the
      # Env that the call makes for it (the slot count and names).
      #
      # `scopes` are the local names that the calling scope can see,
      # innermost first. zr parses the string one scope inside them. A
      # write to a name that they contain goes to their Env. A new name
      # stays in the eval's own Env. `method` is the parameters of the
      # enclosing method, or nil outside a method. `debug_frozen` is
      # RubyVM::InstructionSequence.compile's debug_frozen_string_literal:
      # each String literal keeps where it was made.
      #
      # @rbs source: untyped
      # @rbs file: untyped
      # @rbs line: _ToInt
      # @rbs scopes: Array[Array[Symbol]]
      # @rbs method: untyped
      # @rbs using: Integer?
      # @rbs warn_now: bool
      # @rbs debug_frozen: bool
      # @rbs return: [Integer, Integer, Integer, Integer, Array[Integer], Integer?]
      def compile(source, file, line = 1, scopes = [], method = nil, using: nil, warn_now: false, debug_frozen: false)
        Eval.plainly { compiled(source, file, line, scopes, method, using: using, warn_now: warn_now, debug_frozen: debug_frozen) }
      rescue Hir::Invalid => e
        # Ruby reads a regexp literal when it compiles the string around it,
        # so an invalid pattern is a syntax error, not a run-time error. A
        # build exits with status 3 and gives the line. Here the program is
        # running, so it gets an error that it can rescue.
        syntax = SyntaxError.new(e.message)
        syntax.set_backtrace(caller_locations(0))
        raise syntax
      rescue SyntaxError => e
        # The backtrace starts at the eval call, unless the error refers
        # only to the string (for example, a stray `yield`).
        e.set_backtrace(caller_locations(0)) unless e.backtrace == [e.path]
        raise e
      end

      # Code that the interpreter's `compile` deferred (Kernel.run_code).
      # This compile gives machine code and defers none, so no code
      # comes here.
      #: (untyped code, untyped _self_, untyped _cref, Binding _scope) -> bot
      def walk_code(code, _self_, _cref, _scope) = raise TypeError, "no deferred code to walk: #{code.class}"

      # The toplevel address of the file at `path`, compiled as a required
      # file: its own scope, under main and Object. A file in the extensions
      # (`Library::Layout::EXT`) is part of the runtime, where `Primitive`
      # resolves.
      #
      # The machine code of a file is never freed, so a file that a program
      # loads again with the same source runs the code of its first compile.
      # Under Coverage, or a TracePoint in a program built without trace
      # events, the code differs, so each load compiles.
      #: (String path) -> Integer
      def compile_file(path)
        Eval.plainly do
          # Source bytes, as the parser reads a file: never transcoded to
          # the default internal encoding.
          source = File.binread(path).force_encoding(Encoding::UTF_8)
          coverage = Eval.covering
          reuse = coverage.nil? && !@runtime.traced_for_now?
          key = [-path, -source] #: [String, String]
          if reuse && @files.key?(key)
            # The path's spots are this code's again.
            top, @file_spots[path] = @files.fetch(key)
            next top
          end

          top = (kept_file(path, source) if reuse) || compiled_file(path, source, coverage, keep: reuse)
          @files[key] = [top, @file_spots[path]] if reuse
          top
        end
      end

      private

      # The toplevel of the code that an earlier run kept for the file
      # (`Cache::Loaded`), placed in this process, or nil.
      #: (String path, String source) -> Integer?
      def kept_file(path, source)
        cache = loaded_cache
        return nil if cache.nil? || cache.verify?

        entry = cache.take(cache.key("file", path, source, @runtime.tracing?), @aliases) or return nil
        @file_spots[path] = entry.spots
        place(entry.unit).fetch(entry.top)
      end

      # Compiles the file and places its code. `keep` lets the code go to
      # the cache, under a toplevel name from its key, so that the code is
      # the same in every run.
      #: (String path, String source, untyped coverage, keep: bool) -> Integer
      def compiled_file(path, source, coverage, keep:)
        cache = loaded_cache if keep
        key = cache&.key("file", path, source, @runtime.tracing?)
        @count += 1
        name = key ? "zr_load_#{key[0, 16]}" : "zr_load_#{@count}"
        Timing.phase("compiling #{path}", "compiled #{File.basename(path)}") do
          # While Coverage measures, the file gets its :line events, its def
          # sites and its branch counters, after those of the program, and
          # Coverage learns which of its lines can run, where each of its
          # methods is, and its branches.
          base = coverage&.send(:next_def_site)
          branch_base = coverage&.send(:next_branch_id)
          taken = @runtime.activations
          asked = {} #: Hash[Symbol, Symbol?]
          aliases = ->(old) { asked[old] = @aliases.call(old) }
          # The file's `using` entries come after every entry in use, as an
          # eval's do (`compiled`): numbered from 0, they would take the
          # entries of the program and of eval support (prism's parser).
          hir = Hir.build(source, path, BuildOptions.new(trace: @runtime.tracing?), program: false, def_base: base, branch_base: branch_base,
                                                                                    activations: taken, aliases: aliases)
          @file_spots[path] = (hir.spots || {}).fetch(path, "")
          @runtime.take_activations(hir.activations)
          coverage&.send(:compiled_lines!, hir.coverable, hir.defs, false, hir.branches)
          # Before the lowering, which lets go of each unit's source.
          read = read_files(hir, path)
          ext = Library::Roots.internal_library?(path)
          functions, data = Zr::Lower.new(hir, @description, @symbols, entry: name, kind: :top, ext: ext, fixed: @fixed).run
          code = unit(functions, data)
          if cache && key && hir.activations == taken
            entry = Cache::Loaded::Entry.new(code, name, @file_spots.fetch(path) || "", read, asked, nil)
            check_kept(cache, key, entry) if cache.verify?
            cache.keep(key, entry)
          end
          place(code).fetch(name)
        end
      end

      # The path and the SHA-256 of each file other than `path` that the
      # compile of `path` read: the files that its literal requires
      # compiled in.
      #: (Hir::Program hir, String path) -> Hash[String, String]
      def read_files(hir, path)
        hir.units.filter_map do |unit|
          source = unit.source
          [unit.file, Digest::SHA256.hexdigest(source)] if source && unit.file != path && unit.file.start_with?("/")
        end.to_h
      end

      # `ZR_CODE_CACHE=verify`: the code that the cache has for `key` must
      # be the code of this compile.
      #: (Cache::Loaded cache, String key, Cache::Loaded::Entry entry) -> void
      def check_kept(cache, key, entry)
        kept = cache.take(key, @aliases) or return
        return if Marshal.dump(kept.unit) == Marshal.dump(entry.unit)

        raise "zr: the code that the cache kept for #{key} differs from the code of a new compile"
      end

      # The code cache of the files that this program compiles as it runs,
      # or nil when it is off. A kept file's code holds the kernel's ids and
      # calls into the kernel and the core by name, so the compiler's files,
      # the kernel's description and names, and the library directories
      # that its requires search are what it depends on in this program.
      #: () -> Cache::Loaded?
      def loaded_cache
        return @loaded if defined?(@loaded)

        fixed = @fixed or return @loaded = nil
        stamp = Cache::Store.key(RUBY_PLATFORM, *Runtime.sources.sort.flatten, Machine::Description::KERNEL, *fixed.keys,
                                 *Runtime.library_roots)
        @loaded = Cache::Loaded.for(stamp)
      end

      # Numbers the code's symbols and sites in this process's table, and
      # loads it. Returns its symbols.
      #: (Obj::Unit code) -> Hash[String, Integer]
      def place(code)
        SymbolNumbering.number(code.data, @symbols, @description.const_for("SYMBOL_TAG") || raise("the kernel declares no SYMBOL_TAG"))
        Obj::JIT.load(code, syscalls: @syscalls, arch: ARCH)
      end

      # @rbs source: untyped
      # @rbs file: untyped
      # @rbs line: _ToInt
      # @rbs scopes: Array[Array[Symbol]]
      # @rbs method: untyped
      # @rbs using: Integer?
      # @rbs warn_now: bool
      # @rbs debug_frozen: bool
      # @rbs return: [Integer, Integer, Integer, Integer, Array[Integer], Integer?]
      def compiled(source, file, line, scopes, method, using:, warn_now:, debug_frozen: false)
        source = Eval.string(source)
        file = Eval.string(file)
        # eval_make_iseq: a source that is not ASCII compatible cannot be read.
        raise ArgumentError, "invalid source encoding" unless source.encoding.ascii_compatible?

        coverage = Eval.covering
        # The machine code of an eval is never freed, so a string that runs
        # again, in a scope of the same shape, runs the code that its first
        # compile made, or raises a copy of the error that its first compile
        # raised. Coverage changes the code, and so does a TracePoint enabled
        # in a program built without trace events, so under them each eval
        # compiles. So does an eval that takes `using` entries.
        plain_new = plain_new?
        keep = keep_script_lines?
        key = [-source, source.encoding, -file, line.to_int, scopes, method, using, warn_now, debug_frozen, plain_new, keep]
        reuse = coverage.nil? && !@runtime.traced_for_now?
        if reuse && (kept = @compiled[key])
          raise warned(kept.dup) if kept.is_a?(Exception)

          return kept
        end

        taken = @runtime.activations
        # A later run can take the code from the disk too (`Cache::Loaded`),
        # unless the code holds a number of this run: a `using` entry, or
        # the index of its kept script lines.
        cache = loaded_cache if reuse && using.nil? && !keep
        disk = cache&.key("eval", source, source.encoding, file, line.to_int, scopes, method, warn_now, debug_frozen, plain_new,
                          @runtime.tracing?)
        if cache && disk && !cache.verify? && (entry = cache.take(disk, @aliases))
          locals, used = entry.shape || raise("zr: an eval's cache entry has no shape")
          return @compiled[key] = placed_eval(entry.unit, entry.top, locals, used)
        end

        @count += 1
        name = disk ? "zr_eval_#{disk[0, 16]}" : "zr_eval_#{@count}"
        asked = {} #: Hash[Symbol, Symbol?]
        # A `using` entry is a slot in one table that the whole program
        # shares. The build numbered the program's own entries, and all are
        # in use before the first line runs. So an eval takes the next free
        # entries, and takes them now, because no other code runs before
        # the next compile.
        begin
          switches = Hir::Switches.new(debug_frozen_string_literal: debug_frozen, keep_script_lines: keep)
          # Under `eval: true`, the eval gets its def sites and branch
          # counters too, after those already in use.
          measured = coverage&.send(:measures_evals?)
          hir = Hir.build(source, file, BuildOptions.new(trace: @runtime.tracing?, switches: switches), program: false,
                          line: line.to_int, scopes: [*scopes.reverse, []], method: method, activations: @runtime.activations, using: using,
                          def_base: (coverage.send(:next_def_site) if measured), branch_base: (coverage.send(:next_branch_id) if measured),
                          aliases: ->(old) { asked[old] = @aliases.call(old) })
        rescue Hir::Invalid, SyntaxError => e
          @compiled[key] = e.dup if reuse
          raise warned(e)
        end
        @runtime.take_activations(hir.activations)
        # RubyVM::InstructionSequence.compile: the parser warns as it reads,
        # not when the code runs. A kept copy would not warn.
        warned_now = warn_now && hir.warnings.any?
        if warn_now
          hir.warnings.each { |text| parse_warning(text) }
          hir.warnings.clear
        end
        Eval.cover_eval(coverage, hir, source, line.to_int) if coverage
        script = keep ? kept_script((hir.spots || {}).fetch(file, ""), source, line.to_int) : 0
        read = read_files(hir, file)
        functions, data = Zr::Lower.new(hir, @description, @symbols, entry: name, kind: :eval, outer: outer(scopes), plain_new: plain_new,
                                                                     script: script, fixed: @fixed).run
        compiled = unit(functions, data)
        if cache && disk && hir.activations == taken && !warned_now
          entry = Cache::Loaded::Entry.new(compiled, name, "", read, asked, [hir.locals.size, hir.using])
          check_kept(cache, disk, entry) if cache.verify?
          cache.keep(disk, entry)
        end
        code = placed_eval(compiled, name, hir.locals.size, hir.using)
        @compiled[key] = code if reuse && hir.activations == taken
        code
      end

      # An eval's code, placed: its toplevel's address, its FrameMeta, its
      # Env's slot count and names, the metas of its scopes, and its `using`
      # entry (`compile`).
      #: (Obj::Unit compiled, String name, Integer locals, Integer? used) -> [Integer, Integer, Integer, Integer, Array[Integer], Integer?]
      def placed_eval(compiled, name, locals, used)
        symbols = place(compiled)
        metas = symbols.select { |symbol, _| symbol.start_with?("zr_meta_") }.values
        [symbols.fetch(name), symbols.fetch("zr_meta_#{name}"), locals, symbols.fetch("zr_locals_#{name}"), metas, used]
      end

      # Whether ruby keeps the script lines of the code that it compiles
      # (RubyVM.keep_script_lines).
      #: () -> bool
      def keep_script_lines?
        vm = Object.const_get(:RubyVM) #: untyped
        vm.keep_script_lines ? true : false
      end

      # Whether the program turned off CRuby's specialized instructions
      # (RubyVM::InstructionSequence.compile_option), so `new` is a send.
      #: () -> bool
      def plain_new?
        vm = Object.const_get(:RubyVM) #: untyped
        vm::InstructionSequence.compile_option[:specialized_instruction] == false
      end

      # An error of an eval's code that does not parse: the parser's
      # warnings print first, as ruby's parser prints them while it reads.
      # A kept copy has them too, so each eval of the code prints them.
      #: (Exception error) -> Exception
      def warned(error)
        return error unless error.instance_variable_defined?(:@zr_warnings)

        warnings = error.remove_instance_variable(:@zr_warnings) #: Array[String]
        warnings.each { |text| parse_warning(text) }
        error
      end

      # A warning of the parser, as zr_parse_warning writes it: one that
      # only a true $VERBOSE prints starts with VERBOSE_WARNING.
      #: (String text) -> void
      def parse_warning(text)
        verbose = text.start_with?(Hir::Build::Loader::VERBOSE_WARNING)
        return if $VERBOSE.nil? || (verbose && !$VERBOSE)

        Warning.warn("#{verbose ? text[1..] : text}\n")
      end

      # The Outer chain for `scopes`, innermost first, in lowering order:
      # one step out for each Env that the calling frame can see.
      #: (Array[Array[Symbol]] scopes) -> Lower::Outer?
      def outer(scopes)
        scopes.reverse.reduce(
          nil #: Lower::Outer?
        ) { |out, names| Zr::Lower::Outer.new(names, out) }
      end

      # Runs the same passes and checks as a build, so eval'd code matches
      # the code of the program around it. `Zr::Lower#run` without a block
      # gives only IR functions.
      #: (Array[IR::Function | Obj::Code] lowered, Array[Obj::Datum] data) -> Obj::Unit
      def unit(lowered, data)
        functions = lowered #: Array[IR::Function]
        functions.each { |f| IR::Passes.prepare(f) }
        (ARCH == :x86_64 ? Backend::X86_64 : Backend::Aarch64).unit(functions, data)
      end
    end
  end
end
