# frozen_string_literal: true

require_relative "../prism"
require_relative "../paths"
require_relative "../refused"
require_relative "../libraries"
require_relative "../target"
require_relative "node"
require_relative "syntax_report"

module Zr
  module Hir
    class Refused < Zr::Refused; end

    # A form that ruby itself refuses when it compiles, not one that the
    # HIR does not support yet. A build treats it as any other refusal: it
    # stops and gives the line. But a program that compiles this at run
    # time must get what ruby raises, a SyntaxError, and `Zr::Eval` makes
    # it one.
    class Invalid < Refused; end

    # Prism to HIR. A form that the HIR does not support yet is refused,
    # with a message that gives the form and the line. The rule: the same
    # as CRuby, or refused. Never a guess.
    class Build
      # Ruby's own pure-Ruby stdlib, unchanged: the pinned gems' files and
      # vendor/lib's, found when a build calls this (lib/zr/libraries.rb).
      def self.pure = Libraries.root

      # The extensions whose native part is zr's. A file here is part of
      # the runtime, so it can call a kernel def through `Primitive`.
      EXT = File.join(Paths::RUNTIME, "ext")
      # The runtime files whose instance variables a program sees as in
      # ruby: prism's port, which changes the prism gem's nodes after they
      # are built, and openssl's port (its C creates each visible instance
      # variable by name and keeps the rest in hidden slots).
      VISIBLE_IVARS = [
        *%w[mutation ast].map { |name| File.join(EXT, "prism/ruby/#{name}.rb") },
        File.join(EXT, "openssl.so.rb"), *Dir[File.join(EXT, "openssl/ossl/*.rb")].sort
      ].freeze
      # The runtime's own Ruby, the core library and the extensions: code
      # that a TracePoint never sees.
      RUNTIME = Paths::RUNTIME
      # The named calls that a site lowers to a kernel entry with a core
      # fast path (Zr::Lower::Function::Sends::OPT_ENTRIES), with each
      # one's argument count. A call with a different count, or with a
      # block, keywords or a splat, raises or does something different,
      # and only the real call can tell.
      OPT_CALLS = { getbyte: 1, setbyte: 2, push: 1, pop: 0, shift: 0, empty?: 0 }.freeze

      def self.runtime_file?(file) = File.expand_path(file).start_with?("#{RUNTIME}/")

      # The Ruby part of an extension, as its gem ships it. A gem is on
      # the path only after zr ports its native part, so a require of an
      # unsupported one stops with a message, and does not fail halfway.
      GEMS = %w[prism json psych bigdecimal digest syslog socket ffi openssl].map { |name| File.join(Paths::VENDOR, "ext/#{name}/lib") }.freeze
      # A bundled gem that identifies its own files by their directory.
      # That directory must contain only this gem.
      def self.bundled = Libraries.apart

      # The library roots for `target`, in search order: ruby's own, then
      # the OS layer's native parts and tables, then the portable ones,
      # then the gems' Ruby parts, then the bundled gems in their own
      # directories.
      def self.stdlib(target = Target.default)
        (@stdlib ||= {})[target.triple] ||= [pure, File.join(EXT, "os", target.os_layer), EXT, *GEMS, *bundled].freeze
      end

      # The compiler that a program with eval links in, and the
      # tree-walking interpreter for a program that cannot write machine
      # code into itself. Both contain the same front end. `Zr::Eval`
      # gives the back end that each one runs.
      EVAL_COMPILER = File.expand_path("../eval.rb", __dir__)
      EVAL_INTERPRETER = File.expand_path("../eval/walk.rb", __dir__)

      # The eval support file for `target`. `ZR_EVAL=walk` selects the
      # tree-walking interpreter where the eval compiler (JIT) could run.
      # The tests use this to check the interpreter against the JIT.
      def self.eval_file(target = Target.default)
        target.jits? && ENV["ZR_EVAL"] != "walk" ? EVAL_COMPILER : EVAL_INTERPRETER
      end

      # `eval_support` is false for an eval: the program already contains
      # the compiler, so the eval must not compile it again. It is true to
      # build the compiler into a program with eval, or an EvalSupport that
      # is already built (`Zr::EvalSupport`). Then a program with eval
      # refers to eval support's units and does not build them, also for
      # every file that it shares with eval support. Only the end of a
      # build knows if the program evals, so such a program is built again
      # with eval support.
      # `method` is the parameters of the method that an eval's string
      # runs inside, as from Method#parameters, or nil outside a method:
      # a `yield` has a block only inside a method, and a bare `super`
      # passes those parameters.
      def self.program(source, file, roots: [], eval_support: true, line: 1, scopes: nil, method: nil, activations: nil, target: Target.default)
        # The main file's name came from the build's command line, in the
        # build's locale. A program's locale is UTF-8
        # (Encoding.locale_charmap), and the name must not depend on the
        # build machine.
        file = file.dup.force_encoding(::Encoding::UTF_8) if eval_support && file.encoding != ::Encoding::UTF_8
        built = lambda do |external, trace, evals, covers|
          loader = Loader.new(roots + stdlib(target), eval: !eval_support, external: external, trace: trace, evals: evals,
                              covers: covers, activations: activations, prebuilt_eval: eval_support.respond_to?(:units) ? eval_support : nil)
          [loader, loader.unit(file, source, line, scopes, method: method)]
        end
        # A build knows three facts only after it reads every file: that
        # the program uses eval, TracePoint, or Coverage. Each fact needs
        # a different build: with eval support (its files are referred to,
        # not read), with the events armed, or with the branch counters. A
        # prelude can also cause any of them (`binding.irb` loads
        # fileutils, and fileutils evals). So the build repeats: read, add
        # the preludes, and build again while any fact changed. Each fact
        # can only change from false to true, so the loop ends.
        loader = main = preludes = nil
        evals = trace = covers = false
        external = nil
        loop do
          loader, main = built.call(external, trace, evals, covers)
          preludes = eval_support ? Build.preludes(loader, target) : []
          over = loader.evals? && eval_support.respond_to?(:units) ? eval_support : nil
          break if over.equal?(external) && loader.traces? == trace && loader.covers? == covers

          evals = loader.evals?
          external = over
          trace = loader.traces?
          covers = loader.covers?
        end
        # A program with eval numbers its `using` entries here. A compile
        # at run time cannot see how many there are, because an entry
        # under a condition is made only if the condition is true. So all
        # entries are taken before the first line, and a compile at run
        # time starts after the last of them.
        preludes += [Activations.new(loader.activations, 0)] if eval_support && loader.evals? && loader.activations.positive?
        body = preludes.empty? ? main.body : Seq.new([*preludes, main.body], 0)
        body = Seq.new([data(main, loader.data_at(main.file)), body], 0) if loader.data_at(main.file)
        spots = [main, *loader.units].filter_map { |unit| [unit.file, unit.spots] if unit.spots && !unit.spots.empty? }.to_h
        coverable = loader.covers? ? loader.coverable : {}
        Program.new(main.file, main.locals, body, loader.units, main.warnings, eval_support && loader.evals?, loader.entries, loader.tracing?,
                    loader.node_ids, spots, coverable, loader.activations, loader.covers? ? loader.branches : {},
                    loader.covers? ? loader.defs : {})
      end

      # `DATA`, which ruby defines before the first line of a main file
      # that has an `__END__` line: a File at the byte after that line.
      def self.data(main, at)
        made = Send.new(Core.new(:File, 0), :data, [Literal.new(main.source, 0), Literal.new(at, 0), Literal.new(Paths.shown(main.file), 0)], 0, false)
        ConstWrite.new(nil, :DATA, made, 0)
      end

      # Each prelude whose loader flag is set, in the program's load
      # order: rbconfig before the gems that read it, and the compiler
      # before all that a compile at run time can reach.
      #
      # A prelude is read when it is taken, and it can set another flag
      # (`irb_session` requires irb, which requires fileutils, which
      # evals). So the table is walked again until a walk takes nothing.
      # The result is in table order, not in the order that the flags
      # were set.
      def self.preludes(loader, target)
        asking = {
          configures?: -> { [rbconfig(loader)] },
          evals?: -> { [eval_require(loader, target)] },
          gems?: -> { rubygems(loader) },
          normalizes?: -> { [normalizer(loader)] },
          pretty_prints?: -> { [pretty_printer(loader)] },
          irbs?: -> { [irb_session(loader)] },
          asts?: -> { [ast_translator(loader)] }
        }
        taken = {}
        while (flag = asking.each_key.find { |name| !taken.key?(name) && loader.public_send(name) })
          taken[flag] = asking.fetch(flag).call
        end
        asking.each_key.flat_map { |flag| taken.fetch(flag, []) }
      end

      # Only the compiler, as the units of eval support. The loader built
      # them, and its flags tell what else a program that links them in
      # needs. Eval support also contains the preludes (rbconfig, the
      # normalizer, the pretty printer, the syntax tree translator): a
      # program with eval can need any of them, and here they are lowered
      # once, not with each such program.
      def self.eval_support(target = Target.default)
        Loader.new(stdlib(target)).tap do |loader|
          eval_require(loader, target)
          rubygems(loader)
          rbconfig(loader)
          normalizer(loader)
          pretty_printer(loader)
          irb_session(loader)
          ast_translator(loader)
        end
      end

      # rubygems and bundled_gems, which ruby loads before a program's
      # first line. A zr program loads them at boot if one of its files
      # uses Gem or Bundler, calls `gem` or requires rubygems. Its
      # compiler then already contains them.
      def self.rubygems_files = %w[rubygems bundled_gems].map { |name| File.join(pure, "#{name}.rb") }
      def self.ahead = [File.join(pure, "rubygems"), *rubygems_files]
      # The files of rubygems' autoloads that its boot reads.
      def self.booted = %w[dependency path_support requirement util version].map { |name| File.join(pure, "rubygems/#{name}.rb") }

      def self.rubygems(loader)
        rubygems_files.map { |path| Require.new(:require, File.basename(path, ".rb"), path, loader.add(path), 0) }
      end

      # The file that arms String#unicode_normalize's load of ruby's own
      # normalize.rb. It is a runtime file, so it is not in
      # $LOADED_FEATURES. The load that it arms (at the first call) is.
      NORMALIZER = File.join(EXT, "zr/normalizer.rb")

      def self.normalizer(loader)
        Require.new(:hidden, "zr/normalizer", NORMALIZER, loader.add(NORMALIZER), 0)
      end

      # The file that arms Kernel#pp's load of ruby's own pp.rb, as
      # CRuby's prelude requires it on the first call.
      PRETTY_PRINTER = File.join(EXT, "zr/pretty_printer.rb")
      IRB_SESSION = File.join(EXT, "zr/irb_session.rb")
      SYNTAX_TREE = File.join(EXT, "zr/syntax_tree.rb")

      # The file that loads RubyVM::AbstractSyntaxTree's translator. A
      # program that uses the module loads it before its body. Both are
      # not in $LOADED_FEATURES.
      def self.ast_translator(loader)
        Require.new(:hidden, "zr/syntax_tree", SYNTAX_TREE, loader.hidden(SYNTAX_TREE), 0)
      end

      def self.pretty_printer(loader)
        Require.new(:hidden, "zr/pretty_printer", PRETTY_PRINTER, loader.add(PRETTY_PRINTER), 0)
      end

      # The messages that irb loads for its locale. irb finds this file by
      # a search of $LOAD_PATH, and reads the first match. A zr program
      # contains its files and has no directory to search. So the program
      # includes it: added and not required, because irb loads it and a
      # load does not change $LOADED_FEATURES.
      def self.irb_messages = File.join(pure, "irb/lc/error.rb")

      # The file that arms Binding#irb's load of irb, as CRuby's prelude
      # requires it on the first call.
      def self.irb_session(loader)
        loader.add(irb_messages)
        Require.new(:hidden, "zr/irb_session", IRB_SESSION, loader.add(IRB_SESSION), 0)
      end

      # `rbconfig`, which ruby loads before a program's first line
      # (rubygems requires it at boot). A zr program includes it if one of
      # its files uses `RbConfig` or requires it. So the constant exists
      # and `require "rbconfig"` returns false, as in ruby.
      def self.rbconfig(loader)
        path = loader.resolve(:require, "rbconfig", EXT)
        Require.new(:require, "rbconfig", path, loader.add(path), 0)
      end

      # A require of eval support, before all other code of the program.
      # Only a program that uses eval links in the compiler, so a program
      # without eval links nothing more. The program did not require it,
      # so what it loads is not in $LOADED_FEATURES.
      def self.eval_require(loader, target = Target.default)
        path = eval_file(target)
        Require.new(:hidden, "zr/eval", path, loader.hidden(path), 0)
      end

      # A program that calls one of these compiles ruby at run time. The
      # block forms do not: only a string argument needs a compiler.
      EVAL_FORMS = %i[class_eval module_eval instance_eval].freeze

      # The sends that call the method given by a leading Symbol, and the
      # fetches that return it for a later call.
      SENDS = %i[send __send__ public_send].freeze
      FETCHES = %i[method public_method instance_method].freeze

      # Whether a call of `name` with `argc` arguments compiles ruby that
      # runs in the caller's frame. `named` is the first argument if it is
      # a literal Symbol, so the check sees through a send or a fetch to
      # the method.
      #
      # This result has two uses. A program with such a call links in the
      # compiler. And the enclosing method arms the catch for a `return`
      # in the source, because that return belongs to the method, not to
      # the eval.
      def self.eval_call?(name, named: nil, argc: 0)
        return eval_call?(named, argc: argc - 1) if named && SENDS.include?(name)
        # The call comes later, with arguments this site cannot see.
        return named == :eval || EVAL_FORMS.include?(named) if named && FETCHES.include?(name)

        name == :eval || (EVAL_FORMS.include?(name) && argc.positive?)
      end

      # The files that a program reaches through require, require_relative
      # and load, each parsed and built once. A require searches the
      # roots: the -I roots, and the directories that a file adds to
      # $LOAD_PATH with a literal (`$LOAD_PATH.unshift(File.expand_path
      # ("lib", __dir__))` and similar), read before the file's body.
      class Loader
        attr_reader :units

        # The prism node id of each HIR node, by identity.
        attr_reader :node_ids

        # `external` is an EvalSupport that is already built. A file in it
        # is referred to by its entry, and needs nothing that eval support
        # does not have.
        # `deferred` lists features that a literal require leaves to run
        # time, which finds them in $LOAD_PATH as for a computed name. The
        # gem prelude's libraries require a parser only for an error that
        # this runtime finds differently.
        # `preloaded` are the features for which a require returns false.
        # The gem prelude's own build loads them.
        # `ahead` lists the files that load at boot only what they run
        # there. In these files, a require inside a method waits for run
        # time, which finds and compiles the file then. So does an autoload
        # of a file outside `booted` (the files that the boot reads).
        def initialize(roots, eval: false, external: nil, trace: false, evals: false, covers: false, activations: nil,
                       deferred: [], preloaded: PRELOADED, ahead: Build.ahead, booted: Build.booted, prebuilt_eval: nil)
          @deferred = deferred
          @data = {}
          @prebuilt_eval = external ? nil : prebuilt_eval
          @preloaded = preloaded
          @ahead = ahead
          @booted = booted
          @node_ids = {}.compare_by_identity
          @gems = false
          @eval = eval
          @trace = trace
          @traces = false
          @covers = covers
          @coverable = {}
          @branches = {}
          @branch_count = 0
          @defs = {}
          @def_count = 0
          @roots = roots.map { |r| File.expand_path(r) }
          @units = []
          @index = external ? external.units.dup : {}
          # A build that already read the program knows that it evals. A
          # build with eval support cannot find it again, because the
          # files that told it are in eval support and are not read.
          @evals = evals
          @normalizes = external&.normalizes? || false
          @pretty_prints = external&.pretty_prints? || false
          @irbs = external&.irbs? || false
          @asts = false
          @configures = external&.configures? || false
          # A `using` entry is a slot in one table that the whole program
          # shares, so a build must not use an entry that running code
          # already uses. A program with eval continues after eval
          # support's entries (its files, for example the prism port,
          # activate refinements when they load). A compile at run time
          # continues after the entries of its program.
          @activations = activations || external&.activations || 0
          @back_refs = {}
          @alias_flags = {}
        end

        # `alias $MATCH $&` and similar: the old name is in the frame, not
        # the global table, so the new name is a second name that the
        # lowering resolves. It does not write a global entry. All of them
        # come from English.rb.
        def back_ref(name) = @back_refs[name]

        # Whether a file uses TracePoint or set_trace_func, and whether
        # this build fires the events that a TracePoint listens for.
        def traces? = @traces
        def tracing? = @trace

        # The names in a program that wants `:line` events. The source
        # bytes are checked first, because almost no file contains these
        # words, and a regexp is much faster than a tree walk. If a file
        # contains one, the tree is walked, so a word in a comment does
        # not arm the events for every statement and cause a second build.
        TRACE_NAMES = /\b(?:TracePoint|set_trace_func|add_trace_func|Coverage)\b/
        TRACE_CONSTANTS = %i[TracePoint Coverage].freeze
        TRACE_CALLS = %i[set_trace_func add_trace_func].freeze
        TRACE_WORDS = %w[TracePoint Coverage set_trace_func add_trace_func].freeze
        COVERAGE_CONSTANTS = %i[Coverage].freeze
        COVERAGE_WORDS = %w[Coverage].freeze

        def names_tracing?(tree) = names_of?(tree, TRACE_CONSTANTS, TRACE_CALLS, TRACE_WORDS)

        def names_coverage?(tree) = names_of?(tree, COVERAGE_CONSTANTS, [], COVERAGE_WORDS)

        # Whether the tree uses one of `constants`, calls one of `calls`,
        # or contains one of `words` as a symbol or a string. The words
        # make this as safe as a plain regexp: a name got by `const_get` of
        # a string also counts. To arm a program that does not trace costs
        # time, but to miss one that does gives wrong output.
        def names_of?(tree, constants, calls, words)
          !tree.breadth_first_search do |n|
            case n
            when Prism::ConstantReadNode then constants.include?(n.name)
            when Prism::ConstantPathNode then n.parent.nil? && constants.include?(n.name)
            when Prism::CallNode then calls.include?(n.name)
            when Prism::SymbolNode, Prism::StringNode then words.include?(n.unescaped)
            end
          end.nil?
        end

        # Whether a file uses Coverage. Also, for each file, its line count
        # and the lines where a traced build fires :line events. Coverage
        # returns nil for the other lines and counts these.
        def covers? = @covers
        COVERAGE_NAMES = /\bCoverage\b/
        attr_reader :coverable

        def line_event!(file, line)
          @coverable[file]&.last&.push(line)
        end

        # The branch records of each measured file, in Coverage's order: a
        # root, then its branches, then the next root.
        attr_reader :branches

        # Adds a record for branch `kind` over `span`, and returns
        # `[id, index]`. `id` is its `Cover` id, unique in the program,
        # because one counter array contains all files' counters. `index`
        # is the record's position in its file: Coverage shows it, and a
        # branch refers to its root by it. `under` is the root's index for
        # a branch, nil for a root.
        def branch!(file, kind, span, under: nil)
          rows = (@branches[file] ||= [])
          id = @branch_count
          @branch_count += 1
          rows << [kind, id, under, *span]
          [id, rows.size - 1]
        end

        # The location of each scope that Coverage can report as a method,
        # by file. A `def` and a block both get a record, because
        # `define_method` makes a method from a block and ruby gives that
        # method the block's location. Only the run knows which becomes a
        # method, so the record is only the span. The name and owner come
        # from the definition that uses it.
        attr_reader :defs

        def def_site!(file, span)
          id = @def_count
          @def_count += 1
          (@defs[file] ||= []) << [id, *span]
          id
        end

        # The number of `using` entries in use after this build, and the
        # next entry that it takes.
        attr_reader :activations

        def next_activation = @activations.tap { @activations += 1 }

        # `flag` is the global that a conditional alias sets when it runs,
        # or nil for an alias that always runs.
        def back_ref!(new_name, old_name, flag = nil)
          @back_refs[new_name] = old_name
          @alias_flags[new_name] = flag
        end

        def alias_flag(name) = @alias_flags[name]

        def evals? = @evals

        def deferred?(feature) = @deferred.include?(feature)

        def ahead?(file) = @ahead.any? { |dir| file.start_with?(dir) }

        def booted?(path) = @booted.include?(path)

        attr_reader :preloaded

        # A file that the program requires but that only run time can find.
        def compiles_at_run_time!
          @evals = true
        end

        # The calls that add to $LOAD_PATH, or take from it.
        LOAD_PATH_CHANGES = %i[unshift push << concat insert prepend append replace clear shift pop delete delete_at delete_if
                               reject! select! filter! keep_if map! collect! []= fill].freeze

        # A change to $LOAD_PATH that the compiler cannot follow (anything
        # other than a literal directory added) can make a require find a
        # file that was not compiled in, so the program links in the
        # compiler.
        def load_path_changed!(node, file)
          return unless node.receiver.is_a?(Prism::GlobalVariableReadNode) && %i[$LOAD_PATH $:].include?(node.receiver.name)
          return unless LOAD_PATH_CHANGES.include?(node.name)

          literal = %i[unshift push <<].include?(node.name) && node.arguments&.arguments&.all? { |a| literal_path(a, file) }
          @evals = true unless literal
        end

        # Whether this build is an eval. A string of ruby cannot add a unit
        # to a program that is already linked, and it cannot see the
        # methods of its enclosing class. So `require` and `load` there are
        # normal sends, and dispatch decides.
        def eval? = @eval

        # Each file that this loader reached, by path: its unit's index, or
        # its entry in an external EvalSupport.
        def entries = @index

        # The unit at `path` and all that it loads, built as eval support
        # files (hidden).
        def hidden(path)
          @hiding = true
          add(path)
        ensure
          @hiding = false
        end

        # A require, require_relative or load that goes to Kernel's method
        # as a send. Its name is computed, so it can find a file that was
        # not compiled in, and the program links in the compiler to
        # compile that file at run time.
        LOADS = %i[require require_relative load].freeze

        # A program's method that replaces one of these and calls `super`
        # passes a name to Kernel's or Module's method that no site shows.
        def loads_by_def!(node)
          return unless (LOADS.include?(node.name) || node.name == :autoload) && node.body

          supers = node.body.breadth_first_search { |n| n.is_a?(Prism::SuperNode) || n.is_a?(Prism::ForwardingSuperNode) }
          @evals = true if supers
        end

        # `kernel` tells that the call goes to Kernel's method: it has no
        # receiver, or `Kernel` is the receiver. `YAML.load` does not. An
        # `autoload` that gets here has a computed feature, with any
        # receiver, because Module#autoload also takes one.
        def evals!(name, args, kernel: true)
          @evals = true if name == :autoload
          named = args.first.value if args.first.is_a?(Literal) && args.first.value.is_a?(Symbol)
          @evals = true if Build.eval_call?(name, named: named, argc: args.size)
          if named && SENDS.include?(name)
            name, args = named, args.drop(1)
          elsif named && FETCHES.include?(name)
            @evals = true if kernel && LOADS.include?(named)
            return
          end
          @evals = true if kernel && LOADS.include?(name)
          @evals = true if ruby_command?(name, args)
        end

        # The calls that take a command, which runs as Ruby if it is a
        # String. trap's special words select a handler and run no code.
        COMMANDS = %i[trap trace_var].freeze
        TRAP_WORDS = ["", "IGNORE", "SIG_IGN", "DEFAULT", "SIG_DFL", "SYSTEM_DEFAULT", "EXIT"].freeze

        def ruby_command?(name, args)
          return false unless COMMANDS.include?(name)

          command = args[1]
          command.is_a?(Interp) || (command.is_a?(Literal) && command.value.is_a?(String) && !(name == :trap && TRAP_WORDS.include?(command.value)))
        end

        # A program that uses Ruby::Box or RubyVM::InstructionSequence
        # compiles ruby at run time: all code in a box, and every string
        # that an instruction sequence compiles, goes through the compiler.
        COMPILES = %i[Ruby InstructionSequence].freeze

        def compiles!(name)
          @evals = true if COMPILES.include?(name)
          @asts = true if name == :AbstractSyntaxTree
        end

        # Whether a file uses RubyVM::AbstractSyntaxTree. The translator
        # builds its trees from prism.
        def asts? = @asts

        # Whether a file uses rubygems' API. If so, it loads when the
        # program boots, as ruby loads it for every program.
        def gems? = @gems
        GEM_NAMES = %i[Gem Bundler].freeze

        # rubygems evals when it loads, so a program that includes it also
        # links in the compiler.
        def gems!(name)
          return unless GEM_NAMES.include?(name)

          @gems = true
          @evals = true
        end

        # A program that calls one of these includes ruby's normalize.rb,
        # which String loads at the first call, as CRuby does.
        NORMALIZES = %i[unicode_normalize unicode_normalize! unicode_normalized?].freeze
        # A conversion can need the same tables: the Mac's UTF-8 (UTF8-MAC)
        # keeps every character decomposed, and a conversion from it is a
        # normalization.
        ENCODES = %i[encode encode!].freeze

        def normalizes? = @normalizes
        def pretty_prints? = @pretty_prints
        def irbs? = @irbs

        def configures? = @configures
        def configures! = @configures = true

        # Whether a file uses the toplevel `RbConfig`, bare or as
        # `::RbConfig`.
        def names_rbconfig?(tree)
          !tree.breadth_first_search do |n|
            case n
            when Prism::ConstantReadNode then n.name == :RbConfig
            when Prism::ConstantPathNode then n.parent.nil? && n.name == :RbConfig
            end
          end.nil?
        end

        def normalizes!(name, args)
          named = args.first.value if args.first.is_a?(Literal) && args.first.value.is_a?(Symbol)
          @normalizes = true if NORMALIZES.include?(name) || ENCODES.include?(name) ||
                                ((SENDS + FETCHES).include?(name) && (NORMALIZES + ENCODES).include?(named))
          # A program that calls pp includes pp.rb, which the first call loads.
          @pretty_prints = true if name == :pp || ((SENDS + FETCHES).include?(name) && named == :pp)
          # A program that calls irb includes irb, which `binding.irb` loads.
          @irbs = true if name == :irb || ((SENDS + FETCHES).include?(name) && named == :irb)
        end

        # The byte a file's `__END__` data starts at, or nil when it has
        # none.
        def data_at(file) = @data[file]

        def unit(file, source = File.read(file), line = 1, scopes = nil, method: nil)
          result = scopes ? Zr.parse(source, filepath: file, line: line, scopes: scopes) : Zr.parse(source, filepath: file, line: line)
          raise SyntaxReport.error(result, file) unless result.errors.empty?
          if (marker = result.data_loc)
            @data[file] = source.byteindex("\n", marker.start_offset)&.succ || source.bytesize
          end
          stray = scopes && method.nil? && invalid_yields(source, file, line)
          raise stray if stray

          load_path_roots(result.value, file).each do |front, paths|
            front ? @roots.unshift(*paths) : @roots.concat(paths)
          end
          configures! if !configures? && names_rbconfig?(result.value)
          @traces ||= !Build.runtime_file?(file) && TRACE_NAMES.match?(source.b) && names_tracing?(result.value)
          @covers ||= !Build.runtime_file?(file) && COVERAGE_NAMES.match?(source.b) && names_coverage?(result.value)
          @coverable[file] = [source.lines.size, []] if @trace && !Build.runtime_file?(file)
          build = Build.new(file, self, result.encoding, shadowed: shadowed(result.value), root: result.value)
          build.within_method(method, scopes) if scopes && method
          # An activation entry belongs to the program, not the file, so
          # the unit cache cannot keep a file that takes one.
          rows = @activations
          body = build.seq(result.value.statements, hoist: true)
          unless @eval || @hiding || file.start_with?("<") || Build.runtime_file?(file)
            spots = Spots.for(result, source, { filepath: file, line: line })
          end
          Unit.new(file, result.value.locals + build.temps, body, warnings(result, file) + build.warnings, file.start_with?("#{EXT}/"), spots, @hiding,
                   source, @activations != rows)
        end

        # The SyntaxError for a `yield` in an eval string, outside any
        # `def` in the string, when the eval is outside a method: there is
        # no block to yield to. prism reports it only if it does not know
        # about the outer scopes, so parse again without them. Ruby
        # reports each one, one line each.
        def invalid_yields(source, file, line)
          yields = Zr.parse(source, filepath: file, line: line).errors.select { |e| e.type == :invalid_yield }
          return nil if yields.empty?

          SyntaxError.new(yields.map { |e| "#{file}:#{e.location.start_line}: #{e.message}" }.join("\n")).tap do |exc|
            exc.instance_variable_set(:@path, file)
            exc.set_backtrace([file])
          end
        end

        # The definees for which this file defines its own `require`,
        # `require_relative` or `load`. A call in one of them dispatches to
        # that method, so it must not compile the file in.
        def shadowed(node, path = [Object.name], singleton = false, found = {})
          case node
          when Prism::ClassNode, Prism::ModuleNode
            shadowed(node.body, path + [node.constant_path.slice], false, found) if node.body
          when Prism::SingletonClassNode
            shadowed(node.body, path, true, found) if node.body
          when Prism::DefNode
            found[[path.join("::"), !node.receiver.nil? || singleton, node.name]] = true if REQUIRES.include?(node.name)
          else
            node&.child_nodes&.each { |child| shadowed(child, path, singleton, found) }
          end
          found
        end

        # Ruby's parse-time warnings for the file (`key :k is duplicated
        # and overwritten on line 24` and similar), as ruby prints them.
        # prism knows the rules and the line of each. A plain run does not
        # print `-w` level warnings.
        def warnings(result, file)
          result.warnings.filter_map do |w|
            next unless w.level == :default

            "#{Paths.shown(file)}:#{w.location.start_line}: warning: #{w.message}"
          end
        end

        # The index of `path`'s unit, built at first use. The index entry
        # is set before the file is read, so two files that require each
        # other stop where ruby stops: the second require returns false
        # and the first one finishes.
        def add(path)
          return @index[path] if @index.key?(path)
          # After a build finds that the program evals, it will run again
          # with eval support (`Build.program` uses it as `external`). So
          # from here, it refers to each eval support file as that build
          # will, and reads none of them. Without this, `require "rubygems"`
          # (which evals at its first line) reads and builds about a
          # hundred files only to discard them.
          if @prebuilt_eval && @evals && (entry = @prebuilt_eval.units[path])
            return @index[path] = entry
          end

          i = @units.size
          @index[path] = i
          @units << nil
          @units[i] = unit(path)
          i
        end

        # A unit that stops with a message when it runs. An autoload of a
        # feature that this runtime has no file for becomes this: the
        # autoload entry exists, and a read of the constant stops.
        def stop_unit(what, line)
          i = @units.size
          @units << Unit.new(what, [], Stop.new(what, line), [], false)
          i
        end

        # The file for `feature`, required from `from`, or nil.
        def resolve(kind, feature, from)
          if kind == :require_relative
            candidate(File.expand_path(feature, File.dirname(from)))
          elsif feature.start_with?("/", "./", "../", "~")
            # A path relative to the working directory, which the program
            # can change. The requiring file's directory is the second
            # place to look.
            candidate(File.expand_path(feature)) || candidate(File.expand_path(feature, File.dirname(from)))
          else
            @roots.each do |root|
              found = candidate(File.join(root, feature)) || native(root, feature)
              return found if found
            end
            nil
          end
        end

        # A native extension's name: `strscan.so`, `date.bundle`.
        NATIVE = /\.(?:so|bundle|dylib|o)\z/

        # The file in place of native extension `feature` under `root`:
        # the extension's own Ruby (`strscan.rb`), if the root contains
        # this runtime's native parts.
        def native(root, feature)
          native_root?(root) && feature.match?(NATIVE) ? candidate(File.join(root, feature.sub(NATIVE, ""))) : nil
        end

        # EXT, or an OS layer's directory under it.
        def native_root?(root) = root == EXT || File.dirname(root) == File.join(EXT, "os")

        def candidate(path)
          return path if path.end_with?(".rb") && File.file?(path)

          File.file?("#{path}.rb") ? "#{path}.rb" : nil
        end

        # The directories that a file adds to $LOAD_PATH with a literal, in
        # order: `[true, paths]` for an `unshift`, which puts them before
        # all roots, and `[false, paths]` for `push` and `<<`.
        def load_path_roots(node, file)
          roots = []
          walk = lambda do |n|
            if n.is_a?(Prism::CallNode) && n.receiver.is_a?(Prism::GlobalVariableReadNode) && %i[$LOAD_PATH $:].include?(n.receiver.name) &&
               %i[unshift push <<].include?(n.name) && n.arguments
              paths = n.arguments.arguments.filter_map { |a| literal_path(a, file) }
              roots << [n.name == :unshift, paths] unless paths.empty?
            end
            n.compact_child_nodes.each { |c| walk.call(c) }
          end
          walk.call(node)
          roots
        end

        # The absolute path of a literal: a String, `File.expand_path(str,
        # __dir__)` or `File.join(__dir__, str...)`. nil for all others.
        def literal_path(node, file)
          dir = File.dirname(file)
          case node
          when Prism::StringNode then File.expand_path(node.unescaped)
          when Prism::InterpolatedStringNode
            parts = node.parts
            return nil unless parts.size == 2 && parts[0].is_a?(Prism::EmbeddedStatementsNode) && parts[0].statements&.body&.size == 1 &&
                              dir_call?(parts[0].statements.body[0]) && parts[1].is_a?(Prism::StringNode)

            File.expand_path(dir + parts[1].unescaped)
          when Prism::CallNode
            return nil unless node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :File && node.arguments

            args = node.arguments.arguments
            if node.name == :expand_path && args.size == 2 && args[0].is_a?(Prism::StringNode) && dir_call?(args[1])
              File.expand_path(args[0].unescaped, dir)
            elsif node.name == :join && dir_call?(args[0]) && args[1..].all?(Prism::StringNode)
              File.join(dir, *args[1..].map(&:unescaped))
            end
          end
        end

        def dir_call?(node)
          node.is_a?(Prism::CallNode) && node.name == :__dir__ && node.receiver.nil? && node.arguments.nil?
        end
      end

      def initialize(file, loader = nil, encoding = ::Encoding::UTF_8, shadowed: {}, root: nil)
        @file = file
        @loader = loader
        @root = root
        @node_ids = loader&.node_ids
        @encoding = encoding
        @shadowed = shadowed
        @path = [Object.name]
        @singleton = false
        @body_marks = []
        @block_depth = 0
        @using = nil
        # The number of `using` entries that this build made. `statement`
        # reads it to know if a search of its new statement can find one.
        @usings = 0
        @in_def = false
        @dead = 0
        @activations = -1
        @temps = [[]]
        @scopes = [@temps.first]
        # The line of each scope's last `:line` event, in the compiler's
        # statement order (ruby's last_line).
        @last_lines = [-1]
        @warnings = []
        # The depth of each parameter of the method that an eval runs in,
        # outside the eval's own scope. nil inside a def of the file,
        # whose parameters are in its own scope.
        @def_depths = nil
      end

      # An eval's string runs inside a method. A bare `super` passes the
      # parameters in `rows`, each read from the scope in `scopes`
      # (innermost first) that contains it. A parameter with no name (a
      # destructured one) cannot be passed, so neither `super` can.
      def within_method(rows, scopes)
        return if rows.any? { |_, name| name.nil? || scopes.none? { |names| names.include?(name) } }

        required, optional, post, keywords = [], [], [], []
        rest = kwrest = block = nil
        rows.each do |kind, name|
          case kind
          when :req then (optional.empty? && rest.nil? ? required : post) << name
          when :opt then optional << [name, nil]
          when :rest then rest = name
          when :key, :keyreq then keywords << [name, nil]
          when :keyrest then kwrest = name
          when :nokey then kwrest = :nokey
          when :block then block = name
          end
        end
        @def_params = Params.new(required, optional, rest, post, keywords, kwrest, block)
        @def_depths = rows.to_h { |_, name| [name, 1 + scopes.index { |names| names.include?(name) }] }
      end

      # The warnings ruby's compiler gives for the file's regexp literals,
      # after the parser's own.
      attr_reader :warnings

      # The hidden locals the toplevel scope needs.
      def temps = @temps.first

      # The names of the anonymous parameters `*`, `**`, `&` and `...`,
      # as locals of the def that declares them.
      ANONYMOUS = { rest: :*, kwrest: :**, block: :& }.freeze

      # Builds `body` in a branch that a literal condition never takes,
      # if `never` is true.
      def dead(never)
        @dead += 1 if never
        yield
      ensure
        @dead -= 1 if never
      end

      # Builds `body` one block scope deeper. A `using` in a block at the
      # top level of a file refines the file's own scope, so it applies to
      # the rest of the file after the block, as in ruby.
      def in_block
        @block_depth += 1
        using = @using
        @temps.push([])
        @last_lines.push(-1)
        yield
      ensure
        @block_depth -= 1
        @using = using unless @path == [Object.name] && !@in_def
        @temps.pop
        @last_lines.pop
      end

      # Builds `body` in a new scope: a def or a class body.
      def in_scope
        was = [@block_depth, @def_params, @def_depths]
        @block_depth = 0
        @def_params = nil
        @def_depths = nil
        @temps.push([])
        @scopes.push(@temps.last)
        @last_lines.push(-1)
        yield
      ensure
        @block_depth, @def_params, @def_depths = was
        @temps.pop
        @scopes.pop
        @last_lines.pop
      end

      # A scope's locals: the parser's, then the hidden ones from its body.
      def with_temps(locals) = locals + @temps.last

      # The globals that are in the frame or the task, not the global
      # table. An alias of one is a second name that the lowering resolves.
      FRAME_GVARS = %i[$~ $_ $! $@].freeze

      # The other names ruby gives one global.
      GVAR_ALIASES = {
        :$PROGRAM_NAME => :$0, :$: => :$LOAD_PATH, :$-I => :$LOAD_PATH, :$" => :$LOADED_FEATURES, :$> => :$stdout,
        :$-0 => :$/, :$-F => :$;, :$-v => :$VERBOSE, :$-w => :$VERBOSE, :$-d => :$DEBUG
      }.freeze

      def gvar_name(name)
        GVAR_ALIASES.fetch(name, name)
      end

      # A `$name` read: through an alias of a frame global, `$@` as the
      # backtrace of `$!`, or the global itself.
      def gvar_read(name, line)
        aliased = @loader&.back_ref(name)
        if aliased && (flag = @loader.alias_flag(name))
          return If.new(GvarRead.new(flag, line), expr(aliased), GvarRead.new(gvar_name(name), line), line)
        end
        return expr(aliased) if aliased
        return Send.new(GvarRead.new(:$!, line), :backtrace, [], line, false, nil, nil, nil, true) if name == :$@

        GvarRead.new(gvar_name(name), line)
      end

      # `$name = value`: a write through an alias of a frame global goes to
      # that global, and keeps the program's name for error messages.
      # Every back reference is read-only, as `$&` is.
      def gvar_write(name, value, line)
        aliased = @loader&.back_ref(name)
        target = if aliased.is_a?(Prism::GlobalVariableReadNode) then aliased.name
                 elsif aliased then :$&
                 else gvar_name(name)
                 end
        write = GvarWrite.new(target, value, line, target == name ? nil : name)
        flag = aliased && @loader.alias_flag(name)
        flag ? If.new(GvarRead.new(flag, line), write, GvarWrite.new(gvar_name(name), value, line, nil), line) : write
      end

      # `$&`, `` $` ``, `$'` and `$+`: from the last match, or nil if there
      # is none.
      def back_reference(node, line)
        case node.name
        when :$& then BackRef.new(:nth, 0, line)
        when :$` then BackRef.new(:pre, nil, line)
        when :$' then BackRef.new(:post, nil, line)
        when :$+ then BackRef.new(:last, nil, line)
        else refuse(node, "#{node.name} is not lowered yet")
        end
      end

      # `a..b` in a condition is a flip-flop: it is true from the run where
      # the left side is true to the run where the right side is true. The
      # state is a hidden local of the enclosing def, so a block shares its
      # method's state, as in ruby.
      def flip_flop(node, line)
        state = flip_flop_state
        depth = @block_depth
        ends = -> { If.new(end_test(node.right, line), Assign.new(state, depth, Literal.new(false, line), line), nil, line) }
        # `...` waits for the next run before it can turn off. `..` tests
        # the right side at once, so a one-run range ends where it started.
        started = [Assign.new(state, depth, Literal.new(true, line), line)]
        started << ends.call unless node.exclude_end?
        started << Literal.new(true, line)
        If.new(Local.new(state, depth, line),
               Seq.new([ends.call, Literal.new(true, line)], line),
               If.new(end_test(node.left, line), Seq.new(started, line), Literal.new(false, line), line),
               line)
      end

      # An end of a flip-flop. A missing end never fires. An integer
      # literal is a test of the last line read, `$. == n`, as ruby's
      # compiler makes it.
      def end_test(node, line)
        return Literal.new(nil, line) unless node
        return Send.new(gvar_read(:$., line), :==, [expr(node)], line, false) if node.is_a?(Prism::IntegerNode)

        expr(node)
      end

      def flip_flop_state
        @flip_flops = (@flip_flops || 0) + 1
        name = :"%flip_flop#{@flip_flops}"
        @scopes.last << name
        name
      end

      # `# shareable_constant_value:` on a constant write. A value that the
      # compiler knows is a literal is deep-frozen. Any other value must
      # already be shareable, as in ruby.
      def shareable_constant(node, line)
        write = expr(node.write)
        ractor = ConstRead.new(nil, :Ractor, line)
        write.value =
          if node.literal?
            literally_shareable(node.write.value, write.value, constant_written(node.write), line)
          elsif node.experimental_copy?
            Send.new(ractor, :make_shareable, [write.value], line, false, nil, nil, HashLit.new([Literal.new(:copy, line), Literal.new(true, line)], line))
          else
            Send.new(ractor, :make_shareable, [write.value], line, false)
          end
        write
      end

      # `literal`'s value, as prism_compile.c's
      # pm_compile_shareable_constant_value builds it. An Array or Hash
      # literal builds each element the same way, then is made shareable
      # as a whole. A value of only literals is made shareable. Any other
      # value must already be shareable (an interpolated String after
      # deduplication). `top` is the constant's own value, not an element.
      def literally_shareable(node, value, name, line, top: true)
        node, value = unparenthesized(node, value)
        return frozen_literal(node, value, line) if shareable_literal?(node)

        ractor = ConstRead.new(nil, :Ractor, line)
        whole = ->(built) { top ? Send.new(ractor, :make_shareable, [built], line, false) : built }
        if node.is_a?(Prism::ArrayNode) && node.elements.none? { |e| e.is_a?(Prism::SplatNode) || e.is_a?(Prism::KeywordHashNode) }
          value.elements = node.elements.zip(value.elements).map { |e, v| literally_shareable(e, v, name, line, top: false) }
          whole.(value)
        elsif node.is_a?(Prism::HashNode) && node.elements.all?(Prism::AssocNode)
          value.pairs = value.pairs.each_slice(2).zip(node.elements).flat_map do |(key, v), e|
            [key, literally_shareable(e.value.is_a?(Prism::ImplicitNode) ? e.value.value : e.value, v, name, line, top: false)]
          end
          whole.(value)
        else
          value = Send.new(value, :-@, [], line, false) if node.is_a?(Prism::InterpolatedStringNode)
          Send.new(ractor, :ensure_shareable, [value, Literal.new(name, line)], line, false)
        end
      end

      # `(value)`: the one statement inside, and its built value, as
      # compile.c reads through the parentheses of `X = (1..2)`.
      def unparenthesized(node, value)
        while node.is_a?(Prism::ParenthesesNode) && node.body.is_a?(Prism::StatementsNode) && node.body.body.size == 1 &&
              value.is_a?(Seq) && value.stmts.size == 1
          node = node.body.body[0]
          value = value.stmts[0]
        end
        [node, value]
      end

      # Whether CRuby makes a new Range of two String literals at each run.
      # Its peephole optimizer folds the two strings and the newrange into
      # one static Range only if no label is before the first string. A
      # label starts a block's body, a loop's body, the else branch of an
      # `if`, the then branch of an `unless` (a `case` has none), and a
      # body that a rescue covers.
      def after_label?(node)
        @after_label ||= {}.compare_by_identity.tap { |found| labeled(@root, found) if @root }
        @after_label.key?(node)
      end

      def labeled(node, found)
        return if node.nil?

        start = case node
                when Prism::BlockNode, Prism::LambdaNode then node.body
                when Prism::WhileNode, Prism::UntilNode then node.statements
                when Prism::IfNode then node.subsequent
                when Prism::UnlessNode then node.statements
                when Prism::BeginNode then node.rescue_clause && node.statements
                end
        first = leading(start)
        found[first] = true if first
        node.compact_child_nodes.each { |child| labeled(child, found) }
      end

      # The Range whose code comes first in `node`'s code, if any: a
      # receiver comes before its call, a value before the variable that
      # it sets, a condition before its branches.
      def leading(node)
        case node
        when Prism::RangeNode then node
        when Prism::StatementsNode then leading(node.body.first)
        when Prism::ParenthesesNode then leading(node.body)
        when Prism::ElseNode then leading(node.statements)
        when Prism::BeginNode then node.rescue_clause ? nil : leading(node.statements)
        when Prism::IfNode, Prism::UnlessNode then leading(node.predicate)
        when Prism::CallNode then leading(node.receiver)
        when Prism::AndNode, Prism::OrNode then leading(node.left)
        when Prism::ArrayNode then leading(node.elements.first)
        when Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode, Prism::GlobalVariableWriteNode,
             Prism::ClassVariableWriteNode then leading(node.value)
        end
      end

      # A value built only of literals (`shareable_literal?`), frozen when
      # it is built and with no send, as compile.c freezes the object that
      # it makes at compile time. An Array or Hash literal is marked frozen
      # and its elements are built the same way. A String is the shared
      # frozen String of its text. A Range's ends are frozen. All other
      # literals are always frozen.
      def frozen_literal(node, value, line)
        case node
        when Prism::ArrayNode
          value.elements = node.elements.zip(value.elements).map { |e, v| frozen_literal(e, v, line) }
          value.frozen = true
        when Prism::HashNode
          value.pairs = value.pairs.each_slice(2).zip(node.elements).flat_map do |(key, v), e|
            [frozen_literal(e.key, key, line), frozen_literal(e.value, v, line)]
          end
          value.frozen = true
        when Prism::RangeNode
          value.low = frozen_literal(node.left, value.low, line) if node.left
          value.high = frozen_literal(node.right, value.high, line) if node.right
        when Prism::StringNode, Prism::SourceFileNode
          text = value.value
          return FrozenString.new(text, line, text.encoding == ::Encoding::UTF_8)
        end
        value
      end

      # The constant name of a shareable constant write, for the error.
      def constant_written(write)
        write.respond_to?(:name) ? write.name.to_s : write.target.name.to_s
      end

      # Whether a value is built only of literals, so a freeze cannot
      # affect an object that the program still uses. A Range with literal
      # ends counts as the constant's own value, but not as an element:
      # compile.c's static_literal_node_p, which reads an Array's or a
      # Hash's elements, has no case for it, so `[(1..2)]` uses
      # make_shareable.
      def shareable_literal?(node, top: true)
        case node
        when Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode,
             Prism::SymbolNode, Prism::StringNode, Prism::NilNode, Prism::TrueNode, Prism::FalseNode,
             Prism::RegularExpressionNode, Prism::SourceFileNode, Prism::SourceLineNode, Prism::SourceEncodingNode
          true
        when Prism::ArrayNode then node.elements.all? { |e| shareable_literal?(e, top: false) }
        when Prism::HashNode
          node.elements.all? { |e| e.is_a?(Prism::AssocNode) && shareable_literal?(e.key, top: false) && shareable_literal?(e.value, top: false) }
        when Prism::RangeNode
          top && (node.left.nil? || shareable_literal?(node.left, top: false)) && (node.right.nil? || shareable_literal?(node.right, top: false))
        else false
        end
      end

      # A regexp literal's option bits, as Regexp.new takes them.
      # `i`, `x` and `m`, then the two encoding bits: `n` declares the
      # pattern encoding-agnostic, and `e`, `s` and `u` pin it to one.
      def regexp_options(node)
        (node.ignore_case? ? 1 : 0) | (node.extended? ? 2 : 0) | (node.multi_line? ? 4 : 0) |
          (regexp_encoding(node) ? 16 : 0) | (node.ascii_8bit? ? 32 : 0)
      end

      # The encoding that a flag letter sets for the pattern, or nil.
      def regexp_encoding(node)
        if node.euc_jp? then ::Encoding::EUC_JP
        elsif node.windows_31j? then ::Encoding::Windows_31J
        elsif node.utf_8? then ::Encoding::UTF_8
        end
      end

      # Ruby checks the pattern. A pattern that ruby refuses is also a
      # syntax error here.
      def interpolated_regexp(node, line)
        pinned = regexp_encoding(node)
        # Each fragment is a separate String: ruby reads each one in its
        # own encoding before it joins them.
        fragments = ArrayLit.new(interpolation(node, line).parts.map { |part| Interp.new([part], line) }, line)
        args = [fragments, Literal.new(regexp_options(node), line), Literal.new(pinned && ::Encoding.list.index(pinned), line)]
        made = Send.new(ConstRead.new(nil, :Regexp, line), :interpolated, args, line, false)
        node.once? ? RegexpOnce.new(made, line) : made
      end

      # Used in place of $stderr while a check compiles a pattern. It keeps
      # what the engine writes.
      class Written < String
        def write(*parts) = parts.sum { |part| concat(part.to_s) && part.to_s.bytesize }
      end

      # Whether this build keeps the engine's warnings, and does not let
      # the engine print them.
      def keeps_warnings? = !@loader&.eval?

      # What the engine wrote to $stderr while it read `held`. The read is
      # also the check: an invalid pattern raises.
      #
      # The only way to keep those warnings is to replace $stderr and
      # $VERBOSE. A build can do this, because it forks and nothing else
      # in that process writes. An eval compile runs inside the program,
      # where all threads share the two, and where ruby lets the engine
      # warn on the program's stderr (as `eval("/(?:a?)*b/")` does). So
      # there, the pattern is read with no redirection.
      def read_pattern(held, options)
        unless keeps_warnings?
          Regexp.new(held, options)
          return ""
        end

        written = Written.new
        begin
          stderr, $stderr = $stderr, written
          verbose, $VERBOSE = $VERBOSE, false
          Regexp.new(held, options)
          written
        ensure
          $stderr = stderr
          $VERBOSE = verbose
        end
      end

      # The branch that a literal condition always selects, or nil if the
      # program decides. Ruby's compiler writes no code for the other
      # branch and does not read it: `if false then /[q-a]/ end` runs, and
      # `if 1 == 2 then /[q-a]/ end` does not.
      def chooses?(node)
        case node
        when Prism::TrueNode then true
        when Prism::FalseNode, Prism::NilNode then false
        end
      end

      def regexp_literal(node, line, taken = true)
        # This literal's value is not used, so ruby never reads the
        # pattern, and zr does not either. An invalid one here is a
        # program that runs. An interpolated regexp is a Send, not this,
        # and it still runs its parts.
        return Seq.new([], line) unless taken

        pinned = regexp_encoding(node)
        # `n` reads the pattern as bytes, so a non-ASCII escape is valid
        # only there. The check must read it the same way.
        held = node.unescaped.dup.force_encoding(node.ascii_8bit? ? ::Encoding::BINARY : (pinned || node.unescaped.encoding))
        written = read_pattern(held, regexp_options(node) & 7)
        written.scan(/warning: (.*)$/) { |(message)| @warnings << "#{Paths.shown(@file)}:#{line}: warning: #{message}" }
        RegexpLit.new(node.unescaped, regexp_options(node), pinned, line)
      rescue RegexpError => e
        invalid(node, "#{e.message.sub(/: \/.*\z/m, "")}: /#{node.unescaped}/")
      end

      # The parts of an interpolated string, each a String or the value
      # of an embedded expression.
      def interpolation(node, line)
        parts = node.parts.map do |part|
          case part
          when Prism::StringNode then Literal.new(unescaped(part), part.location.start_line)
          when Prism::EmbeddedStatementsNode then part.statements ? seq(part.statements) : Literal.new(nil, line)
          when Prism::EmbeddedVariableNode then expr(part.variable)
          when Prism::InterpolatedStringNode then interpolation(part, line)
          else refuse(part, "#{part.class.name.split("::").last.delete_suffix("Node")} in a string is not lowered yet")
          end
        end
        # A single embedded part is joined to an empty literal, which gives
        # the result's start encoding, as ruby's compiler does.
        parts.unshift(Literal.new(+"", line)) if node.parts.size == 1 && !node.parts[0].is_a?(Prism::StringNode)
        # If refinements are active, each part gets `to_s` at its own site,
        # which does the lookup with them. Ruby folds a String or Symbol
        # part into the text first.
        parts = parts.map { |part| folded?(part) ? part : Send.new(part, :to_s, [], line, false) } if @using
        Interp.new(parts, line)
      end

      def folded?(part)
        part = part.stmts.first if part.is_a?(Seq) && part.stmts.size == 1
        part.is_a?(Interp) || (part.is_a?(Literal) && [String, Symbol, NilClass].include?(part.value.class))
      end

      # `hoist` puts the `BEGIN { }` blocks of a file first, in their
      # order, before anything else runs.
      #
      # A sequence returns its last statement's value, so the value of each
      # earlier statement is never used, in every context.
      def seq(node, hoist: false, taken: true)
        return Seq.new([], 1) if node.nil?

        body = node.body
        body = body.partition { |s| s.is_a?(Prism::PreExecutionNode) }.flatten if hoist
        last = body.size - 1
        Seq.new(body.each_with_index.map { |s, i| statement(s, taken: taken && i == last) }, node.location.start_line)
      end

      # One statement. Each send in it gets the activation that is active
      # at the statement. A `using` changes the activation for the
      # statements after it.
      def statement(node, taken: true)
        # `using_activation` makes every `using` entry, so a statement that
        # made none contains none. Then skip the walk below, which reads
        # all of the new statement, for every statement of every file.
        # Almost no file has a `using`.
        made = @usings
        traced = line_event(node)
        out = using_activation(node) || expr(node, taken: taken)
        out = Seq.new([traced, out], traced.line) if traced
        mark_using(out, {}) if @using
        return out if out.is_a?(Using)
        return out if @usings == made

        nested = usings_in(out, {}).sort_by(&:id)
        return out if nested.empty?

        line = node.location.start_line
        Seq.new([UsingDefaults.new(nested.map { |u| [u.id, u.from] }, line), out], line)
      end

      # The `:line` event ruby's compiler puts before a statement that
      # starts a line of its scope, or nil: pm_compile_node's rule, which
      # reads prism's newline flag. A `begin` with no statements before
      # its rescue stands on the rescue's line.
      def line_event(node)
        return nil unless @loader&.tracing? && node.newline? && !Build.runtime_file?(@file)
        # A `begin` or parentheses start with the statement inside, whose
        # event is the one ruby merges theirs into.
        return nil if node.is_a?(Prism::BeginNode) && node.statements
        return nil if node.is_a?(Prism::ParenthesesNode) && node.body

        line = node.location.start_line
        line = node.rescue_clause.location.start_line if node.is_a?(Prism::BeginNode) && node.statements.nil? && node.rescue_clause
        return nil if @last_lines.last == line

        @last_lines[-1] = line
        @loader.line_event!(@file, line)
        Trace.new(:line, line)
      end

      # A `Cover` for each side of a branch Coverage measures, or nils
      # where it measures nothing. `sides` are `[kind, span]` in the
      # order ruby lists them, which is the source's order except that
      # an `unless` puts its else first; the root is numbered ahead of
      # them, as CRuby numbers a branch and then its sides.
      # The id of the row a `def` or a block claims where it makes a
      # method, or nil where nothing is measured.
      def method_cover(node)
        return nil unless @loader&.covers? && !Build.runtime_file?(@file)

        @loader.def_site!(@file, method_span(node))
      end

      # Where ruby locates a method made from this scope. A lambda's row
      # starts past its `->`, which is where CRuby's iseq for one begins:
      # `define_method(:a, ->(x) { x })` is located at `(x) { x }`. Every
      # other scope stands where it was written.
      def method_span(node)
        return span(node.location) unless node.is_a?(Prism::LambdaNode)

        [node.operator_loc.end_line, node.operator_loc.end_column, node.location.end_line, node.location.end_column]
      end

      def branch_covers(kind, span, sides)
        return [nil] * sides.size unless @loader&.covers? && !Build.runtime_file?(@file)

        _, root = @loader.branch!(@file, kind, span)
        sides.map do |side, where|
          id, = @loader.branch!(@file, side, where, under: root)
          Cover.new(id, where[0])
        end
      end

      # The four numbers Coverage names a branch by: where it starts and
      # where it ends, the columns 0-based as ruby counts them.
      def span(location) = [location.start_line, location.start_column, location.end_line, location.end_column]

      # The sides of an `if`, a ternary or an `elsif`. A then with no
      # statements stands in the empty width just past the predicate,
      # and an else nobody wrote stands over the whole `if`, which is
      # what CRuby records for each.
      def if_sides(node)
        [[:then, node.statements ? span(node.statements.location) : after(node.predicate.location)],
         [:else, node.subsequent ? span(else_location(node.subsequent)) : span(node.location)]]
      end

      # An `unless` writes its then first and ruby numbers its else
      # first, so the two are read back the other way round.
      def unless_sides(node)
        [[:else, node.else_clause ? span(else_location(node.else_clause)) : span(node.location)],
         [:then, node.statements ? span(node.statements.location) : after(node.predicate.location)]]
      end

      # Each `when` or `in` clause, then the else -- which a `case`
      # always has, standing over the whole `case` where the source
      # wrote none, so a subject that matched nothing is still counted.
      def case_sides(node, kind)
        sides = node.conditions.map { |c| [kind, span(c.statements&.location || c.location)] }
        sides << [:else, span(node.else_clause ? else_location(node.else_clause) : node.location)]
      end

      # A loop has one side, its body, or the whole loop where it has
      # none.
      def loop_sides(node) = [[:body, span(node.statements&.location || node.location)]]

      # An `else` stands where its statements do and over the whole
      # clause where it holds none; an `elsif` is a branch of its own and
      # stands over itself.
      def else_location(node)
        return node.location unless node.is_a?(Prism::ElseNode)

        node.statements&.location || node.location
      end

      # The empty width just past `location`.
      def after(location) = [location.end_line, location.end_column, location.end_line, location.end_column]

      # `body` with its branch counted first, or `body` alone. A nil
      # body counts and answers nil, as the side ruby writes nothing for
      # answers nil.
      def covered(cover, body, line)
        return body if cover.nil?

        Seq.new([cover, body || Literal.new(nil, line)], line)
      end

      # The `using` rows a statement holds below its top, which a
      # condition may skip.
      def usings_in(node, seen, out = [])
        return out if node.nil? || seen.key?(node.object_id)

        if node.is_a?(Array)
          node.each { |child| usings_in(child, seen, out) }
          return out
        end
        return out unless node.is_a?(Record)

        seen[node.object_id] = true
        out << node if node.is_a?(Using)
        node.each_pair { |_, child| usings_in(child, seen, out) }
        out
      end

      # `using mod` where ruby permits it: at toplevel or in a class or
      # module body, never inside a method, and never as a send whose
      # answer somebody reads.
      def using_activation(node)
        return nil if @in_def
        return nil unless node.is_a?(Prism::CallNode) && node.name == :using && node.block.nil?
        return nil unless node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)

        args = node.arguments&.arguments
        return nil unless args && args.size == 1 && !args[0].is_a?(Prism::SplatNode)

        value = expr(args[0])
        from = @using.is_a?(Integer) ? @using : -1
        @using = @loader ? @loader.next_activation : (@activations += 1)
        @usings += 1
        Using.new(@using, from, value, node.location.start_line)
      end

      def mark_using(node, seen)
        return if node.nil? || seen.key?(node.object_id)

        if node.is_a?(Array)
          node.each { |child| mark_using(child, seen) }
          return
        end
        return unless node.is_a?(Record)

        seen[node.object_id] = true
        node.using = @using if [Send, Super, AttrOpAssign, IndexOpAssign].any? { |type| node.is_a?(type) } && node.using.nil?
        node.each_pair { |_, child| mark_using(child, seen) }
      end

      # A prism node's HIR, noted with the node's id.
      #
      # `taken` is false where the program never takes this expression's
      # value: a statement before the last of its scope, a `while` body,
      # or a branch a literal condition never chooses. ruby's compiler
      # writes nothing for such an expression, and so reads nothing in
      # it -- which is why `puts 1; /[z-a]/; puts 2` runs where the same
      # literal as a scope's value is a SyntaxError. A regexp is the one
      # literal zr reads as it builds, so it is the one that asks.
      def expr(node, taken: true)
        noted(built(node, taken), node)
      end

      # `hir` came from prism's `node`: the frame of what it runs reports
      # that node's id, as node_id_for_backtrace_location reads it. A HIR
      # node an inner prism node built already keeps the inner one's id.
      def noted(hir, node)
        @node_ids[hir] ||= node.node_id if @node_ids && hir.is_a?(Record)
        hir
      end

      def built(node, taken = true)
        line = node.location.start_line
        case node
        when Prism::StatementsNode then seq(node, taken: taken)
        when Prism::ParenthesesNode then node.body ? expr(node.body, taken: taken) : Literal.new(nil, line)
        when Prism::IntegerNode, Prism::FloatNode then Literal.new(node.value, line)
        # `3r` and `2i` are the core's own, even where self has no Kernel.
        when Prism::RationalNode then Send.new(Core.new(:Kernel, line), :Rational, [Literal.new(node.numerator, line), Literal.new(node.denominator, line)], line, false)
        when Prism::ImaginaryNode then Send.new(Core.new(:Kernel, line), :Complex, [Literal.new(0, line), expr(node.numeric)], line, false)
        when Prism::StringNode then literal_string(node, unescaped(node), line)
        when Prism::SymbolNode then Literal.new(node.unescaped.to_sym, line)
        when Prism::NilNode then Literal.new(nil, line)
        when Prism::TrueNode then Literal.new(true, line)
        when Prism::FalseNode then Literal.new(false, line)
        when Prism::SelfNode then SelfRef.new(line)
        when Prism::CallNode then call(node)
        when Prism::DefNode then define(node)
        when Prism::LocalVariableReadNode then Local.new(node.name, node.depth, line)
        when Prism::LocalVariableWriteNode then Assign.new(node.name, node.depth, expr(node.value), line)
        when Prism::MultiWriteNode then MultiAssign.new(multi_target(node), expr(node.value), line, taken)
        when Prism::LocalVariableOperatorWriteNode
          Assign.new(node.name, node.depth, noted(Send.new(Local.new(node.name, node.depth, line), node.binary_operator, [expr(node.value)], line, false), node), line)
        when Prism::LocalVariableAndWriteNode
          Assign.new(node.name, node.depth, And.new(Local.new(node.name, node.depth, line), expr(node.value), line), line)
        when Prism::LocalVariableOrWriteNode
          Assign.new(node.name, node.depth, Or.new(Local.new(node.name, node.depth, line), expr(node.value), line), line)
        when Prism::LambdaNode
          in_block do
            params, extra = block_params(node.parameters)
            body = node.body ? expr(node.body) : Literal.new(nil, line)
            Lambda.new(noted(Block.new(params, with_temps(node.locals + extra + (params.names - node.locals - extra)), body, line,
                                       node.location.end_line, method_cover(node)), node), line)
          end
        when Prism::ItLocalVariableReadNode then Local.new(IT, 0, line)
        when Prism::UndefNode
          return UndefValue.new(node.names.map { |n| expr(n) }, line) unless node.names.all?(Prism::SymbolNode)

          names = node.names.map { |n| n.unescaped.to_sym }
          Undef.new(names, line)
        when Prism::SuperNode
          args, kwargs, forwarded = arguments(node.arguments)
          Super.new(args, kwargs, node.block ? block(node.block) : forwarded, line)
        when Prism::ForwardingSuperNode then zsuper(node, line)
        when Prism::YieldNode
          args, kwargs, = arguments(node.arguments)
          Yield.new(args, line, kwargs)
        when Prism::BreakNode, Prism::NextNode
          value = jump_value(node.arguments, line)
          node.is_a?(Prism::BreakNode) ? Break.new(value, line) : Next.new(value, line)
        when Prism::IfNode
          chosen = chooses?(node.predicate)
          # The predicate is numbered first, as ruby's compiler writes it
          # first; a predicate ruby decides is the whole branch dropped,
          # and Coverage records nothing for it.
          predicate = expr(node.predicate)
          then_cover, else_cover = chosen.nil? ? branch_covers(:if, span(node.location), if_sides(node)) : [nil, nil]
          If.new(predicate,
                 covered(then_cover, node.statements && dead(chosen == false) { seq(node.statements, taken: taken && chosen != false) }, line),
                 covered(else_cover, node.subsequent && dead(chosen == true) { expr(node.subsequent, taken: taken && chosen != true) }, line), line)
        when Prism::CaseMatchNode then case_match(node, taken)
        when Prism::MatchRequiredNode then match_required(node)
        when Prism::MatchPredicateNode then match_predicate(node)
        when Prism::MatchWriteNode then match_write(node)
        when Prism::UnlessNode
          chosen = chooses?(node.predicate)
          # ruby lists an `unless`'s else ahead of its then, and numbers
          # them that way, though the branch still tests the same way.
          predicate = expr(node.predicate)
          else_cover, then_cover = chosen.nil? ? branch_covers(:unless, span(node.location), unless_sides(node)) : [nil, nil]
          If.new(predicate,
                 covered(else_cover, node.else_clause && dead(chosen == false) { seq(node.else_clause.statements, taken: taken && chosen != false) }, line),
                 covered(then_cover, node.statements && dead(chosen == true) { seq(node.statements, taken: taken && chosen != true) }, line), line)
        when Prism::ElseNode then node.statements ? seq(node.statements, taken: taken) : Literal.new(nil, line)
        # A loop answers nil, so nothing takes the value of its body.
        when Prism::WhileNode
          body, = branch_covers(:while, span(node.location), loop_sides(node))
          While.new(expr(node.predicate), covered(body, node.statements && seq(node.statements, taken: false), line), line,
                    node.begin_modifier?)
        when Prism::UntilNode
          body, = branch_covers(:until, span(node.location), loop_sides(node))
          While.new(falsy(expr(node.predicate), line), covered(body, node.statements && seq(node.statements, taken: false), line), line,
                    node.begin_modifier?)
        when Prism::ReturnNode then Return.new(jump_value(node.arguments, line), line)
        # The left decides, so its value is always taken; the right is
        # the pair's answer and stands where the pair does.
        when Prism::AndNode then And.new(expr(node.left), expr(node.right, taken: taken), line)
        when Prism::OrNode then Or.new(expr(node.left), expr(node.right, taken: taken), line)
        when Prism::ClassNode
          scope, name = constant_path(node.constant_path)
          superclass = node.superclass && expr(node.superclass)
          in_definee(node.constant_path.slice, false) do
            in_scope do
              body = node.body ? expr(node.body) : Literal.new(nil, line)
              ClassDef.new(scope, name, superclass, with_temps(node.locals), body, line, node.location.end_line)
            end
          end
        when Prism::ModuleNode
          scope, name = constant_path(node.constant_path)
          in_definee(node.constant_path.slice, false) do
            in_scope do
              body = node.body ? expr(node.body) : Literal.new(nil, line)
              ModuleDef.new(scope, name, with_temps(node.locals), body, line, node.location.end_line)
            end
          end
        when Prism::SingletonClassNode
          target = expr(node.expression)
          in_definee(nil, true) do
            in_scope do
              body = node.body ? expr(node.body) : Literal.new(nil, line)
              SingletonClassDef.new(target, with_temps(node.locals), body, line, node.location.end_line)
            end
          end
        when Prism::ConstantReadNode
          @loader&.compiles!(node.name)
          gems!(node.name)
          ConstRead.new(nil, node.name, line)
        when Prism::ConstantPathNode
          @loader&.compiles!(node.name)
          gems!(node.name) if node.parent.nil?
          scope, name = constant_path(node)
          ConstRead.new(scope, name, line)
        when Prism::ConstantWriteNode then ConstWrite.new(nil, node.name, expr(node.value), line)
        when Prism::ConstantPathWriteNode
          scope, name = constant_path(node.target)
          ConstWrite.new(scope, name, expr(node.value), line)
        when Prism::InterpolatedStringNode
          if node.frozen? then frozen_literal_string(static_text(node), line)
          # Adjacent literals with nothing interpolated are one literal.
          elsif static_string?(node) then Literal.new(static_text(node), line, !node.mutable?)
          else interpolation(node, line)
          end
        when Prism::SourceFileNode then literal_string(node, Paths.shown(@file), line)
        when Prism::SourceLineNode then Literal.new(line, line)
        when Prism::SourceEncodingNode
          Send.new(ConstRead.new(nil, :Encoding, line), :find, [Literal.new(@encoding.name, line)], line, false)
        when Prism::InterpolatedSymbolNode then Send.new(interpolation(node, line), :to_sym, [], line, false)
        when Prism::XStringNode then Send.new(nil, :`, [Literal.new(node.unescaped, line)], line, false)
        when Prism::NumberedReferenceReadNode then BackRef.new(:nth, node.number, line)
        when Prism::BackReferenceReadNode then back_reference(node, line)
        when Prism::RegularExpressionNode then regexp_literal(node, line, taken)
        when Prism::InterpolatedRegularExpressionNode then interpolated_regexp(node, line)
        when Prism::MatchLastLineNode
          # A bare regexp as a condition matches `$_`.
          Send.new(regexp_literal(node, line), :=~, [GvarRead.new(:$_, line)], line, false)
        when Prism::InterpolatedMatchLastLineNode
          Send.new(interpolated_regexp(node, line), :=~, [GvarRead.new(:$_, line)], line, false)
        when Prism::InterpolatedXStringNode then Send.new(nil, :`, [interpolation(node, line)], line, false)
        when Prism::ArrayNode then ArrayLit.new(node.elements.map { |e| array_element(e, line) }, line)
        when Prism::HashNode then HashLit.new(hash_pairs(node.elements), line)
        when Prism::FlipFlopNode then flip_flop(node, line)
        when Prism::ShareableConstantNode then shareable_constant(node, line)
        when Prism::RangeNode
          # Fixnum and nil ends make one frozen Range for the site, as
          # CRuby's optimizable_range_item_p decides.
          static = [node.left, node.right].all? do |e|
            e.nil? || e.is_a?(Prism::NilNode) || (e.is_a?(Prism::IntegerNode) && e.value.bit_length <= 62)
          end
          low = node.left ? expr(node.left) : Literal.new(nil, line)
          high = node.right ? expr(node.right) : Literal.new(nil, line)
          # Two String literals are one frozen Range of frozen ends for
          # the site where CRuby's peephole folds them into one.
          if node.left.is_a?(Prism::StringNode) && node.right.is_a?(Prism::StringNode) && !after_label?(node)
            static = true
            low = frozen_literal(node.left, low, line)
            high = frozen_literal(node.right, high, line)
          end
          RangeLit.new(low, high, node.exclude_end?, line, static)
        when Prism::InstanceVariableReadNode then IvarRead.new(node.name, line)
        when Prism::GlobalVariableReadNode then gvar_read(node.name, line)
        when Prism::GlobalVariableWriteNode then gvar_write(node.name, expr(node.value), line)
        when Prism::GlobalVariableOperatorWriteNode
          gvar_write(node.name, Send.new(gvar_read(node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        # `x ||= v` is `x || (x = v)`, and `x &&= v` is `x && (x = v)`: the
        # write happens only when it is needed, which a frozen receiver, a
        # global's setter and a constant's redefinition warning can see.
        when Prism::GlobalVariableOrWriteNode then Or.new(gvar_read(node.name, line), gvar_write(node.name, expr(node.value), line), line)
        when Prism::GlobalVariableAndWriteNode then And.new(gvar_read(node.name, line), gvar_write(node.name, expr(node.value), line), line)
        when Prism::ClassVariableReadNode then CvarRead.new(node.name, line)
        when Prism::ClassVariableWriteNode then CvarWrite.new(node.name, expr(node.value), line)
        when Prism::ClassVariableOperatorWriteNode
          CvarWrite.new(node.name, Send.new(CvarRead.new(node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::ClassVariableOrWriteNode
          If.new(Defined.new(:cvar, node.name, line), Or.new(CvarRead.new(node.name, line), CvarWrite.new(node.name, expr(node.value), line), line), CvarWrite.new(node.name, expr(node.value), line), line)
        when Prism::DefinedNode then defined(node.value, line)
        when Prism::ClassVariableAndWriteNode then And.new(CvarRead.new(node.name, line), CvarWrite.new(node.name, expr(node.value), line), line)
        when Prism::ConstantOrWriteNode then ConstOrWrite.new(nil, node.name, expr(node.value), line)
        when Prism::ConstantPathOrWriteNode
          scope, name, prelude = constant_scope(node.target, line)
          with_scope(prelude, ConstOrWrite.new(scope, name, expr(node.value), line), line)
        when Prism::ConstantAndWriteNode
          And.new(ConstRead.new(nil, node.name, line), ConstWrite.new(nil, node.name, expr(node.value), line), line)
        when Prism::ConstantPathAndWriteNode
          scope, name, prelude = constant_scope(node.target, line)
          with_scope(prelude, And.new(ConstRead.new(scope, name, line), ConstWrite.new(scope, name, expr(node.value), line), line), line)
        when Prism::ConstantOperatorWriteNode
          ConstWrite.new(nil, node.name, Send.new(ConstRead.new(nil, node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::ConstantPathOperatorWriteNode
          scope, name, prelude = constant_scope(node.target, line)
          with_scope(prelude, ConstWrite.new(scope, name, Send.new(ConstRead.new(scope, name, line), node.binary_operator, [expr(node.value)], line, false), line), line)
        when Prism::AliasMethodNode
          if node.new_name.is_a?(Prism::SymbolNode) && node.old_name.is_a?(Prism::SymbolNode)
            Alias.new(node.new_name.unescaped.to_sym, node.old_name.unescaped.to_sym, line)
          else
            AliasValue.new(expr(node.new_name), expr(node.old_name), line)
          end
        when Prism::AliasGlobalVariableNode
          if node.old_name.is_a?(Prism::GlobalVariableReadNode) && !FRAME_GVARS.include?(node.old_name.name)
            GvarAlias.new(node.new_name.name, node.old_name.name, line)
          else
            # `$&` is a register of the frame that last matched and not a
            # global, so an alias of one is not a row the runtime can
            # carry: the new name is resolved as this file is lowered.
            # ruby leaves an alias it does not reach undone -- `if false;
            # alias $x $&; end` leaves `$x` nil -- so an alias written
            # where it may not run sets a flag of its own when it does,
            # and each use of the name asks the flag.
            flag = certain_alias?(node) ? nil : :"$%alias#{node.new_name.name}"
            @loader&.back_ref!(node.new_name.name, node.old_name, flag)
            flag ? Seq.new([GvarWrite.new(flag, Literal.new(true, line), line, nil), Literal.new(nil, line)], line) : Literal.new(nil, line)
          end
        when Prism::CaseNode
          covers = branch_covers(:case, span(node.location), case_sides(node, :when))
          clauses = node.conditions.map.with_index do |w, i|
            values = w.conditions.map { |c| c.is_a?(Prism::SplatNode) ? splat(c, line) : expr(c) }
            [values, covered(covers[i], w.statements ? seq(w.statements, taken: taken) : Literal.new(nil, line), line)]
          end
          other = node.else_clause && expr(node.else_clause, taken: taken)
          Case.new(node.predicate && expr(node.predicate), clauses, covered(covers.last, other, line), line)
        when Prism::IndexOperatorWriteNode, Prism::IndexOrWriteNode, Prism::IndexAndWriteNode
          refuse(node, "a block in an index target is not lowered yet") if node.block
          args = index_args(node, line)
          op = case node
               when Prism::IndexOperatorWriteNode then node.binary_operator
               when Prism::IndexOrWriteNode then :or
               else :and
               end
          IndexOpAssign.new(expr(node.receiver), args, op, expr(node.value), line)
        when Prism::CallOperatorWriteNode, Prism::CallOrWriteNode, Prism::CallAndWriteNode
          op = case node
               when Prism::CallOperatorWriteNode then node.binary_operator
               when Prism::CallOrWriteNode then :or
               else :and
               end
          AttrOpAssign.new(expr(node.receiver), node.read_name, op, expr(node.value), line, node.call_operator == "&.")
        when Prism::ForNode then for_loop(node)
        when Prism::PostExecutionNode
          # `END { }` shares the enclosing scope, so its body reads one
          # block deeper as an at_exit block.
          body = deepen(node.statements ? seq(node.statements) : Literal.new(nil, line), 0)
          block = Block.new(Params.new([], [], nil, [], [], nil, nil), [], body, line)
          # It registers once for its site, however often the site runs.
          Once.new(Send.new(Core.new(:Kernel, line), :at_exit, [], line, false, false, block, nil, false), line)
        when Prism::PreExecutionNode
          refuse(node, "BEGIN { } outside the toplevel is not lowered yet") unless @block_depth.zero?
          node.statements ? seq(node.statements) : Literal.new(nil, line)
        when Prism::InstanceVariableWriteNode then IvarWrite.new(node.name, expr(node.value), line)
        when Prism::InstanceVariableOperatorWriteNode
          IvarWrite.new(node.name, Send.new(IvarRead.new(node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::InstanceVariableOrWriteNode
          Or.new(IvarRead.new(node.name, line), IvarWrite.new(node.name, expr(node.value), line), line)
        when Prism::InstanceVariableAndWriteNode
          And.new(IvarRead.new(node.name, line), IvarWrite.new(node.name, expr(node.value), line), line)
        when Prism::BeginNode then protected_region(node, taken)
        when Prism::RescueModifierNode
          clause = Rescue.new([], nil, expr(node.rescue_expression), line)
          Begin.new(expr(node.expression), [clause], nil, nil, line)
        # ruby's compiler writes nothing for a branch it knows is never
        # taken, so a `retry` there is no error wherever it stands.
        when Prism::RetryNode then @dead.positive? ? Literal.new(nil, line) : Retry.new(line)
        when Prism::RedoNode then Redo.new(line)
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
        end
      end

      # `begin ... end` with its clauses; a bare `begin ... end` is its body.
      # A region's body and its `else` answer for the region and stand
      # where it stands. An `ensure` runs for its effect alone and
      # answers nothing, so nothing ever takes its value. A `rescue`
      # body is not the same: ruby reads a regexp there even where the
      # region's own value is dropped.
      def protected_region(node, taken = true)
        line = node.location.start_line
        body = node.statements ? seq(node.statements, taken: taken) : Literal.new(nil, line)
        return body if node.rescue_clause.nil? && node.ensure_clause.nil?

        rescues = []
        clause = node.rescue_clause
        while clause
          rescues << rescue_clause(clause)
          clause = clause.subsequent
        end
        else_body = node.else_clause && (node.else_clause.statements ? seq(node.else_clause.statements, taken: taken) : Literal.new(nil, line))
        ensure_body = node.ensure_clause && (node.ensure_clause.statements ? seq(node.ensure_clause.statements, taken: false) : Literal.new(nil, line))
        Begin.new(body, rescues, else_body, ensure_body, line)
      end

      def rescue_clause(node)
        line = node.location.start_line
        classes = node.exceptions.map { |e| e.is_a?(Prism::SplatNode) ? splat(e, line) : expr(e) }
        Rescue.new(classes, node.reference && target(node.reference), node.statements ? seq(node.statements) : Literal.new(nil, line), line)
      end

      # What `return`, `break` and `next` carry: nothing is nil, one
      # value is itself, several are an Array.
      def jump_value(arguments, line)
        args = arguments&.arguments || []
        return Literal.new(nil, line) if args.empty?

        elements = args.map { |a| a.is_a?(Prism::SplatNode) ? splat(a, line) : expr(a) }
        return elements.first if elements.size == 1 && !elements.first.is_a?(Splat)

        ArrayLit.new(elements, line)
      end

      # `[scope, name]` of a constant path: nil for a bare name, :top for
      # `::Name`, else the expression before the last `::`.
      def constant_path(node)
        case node
        when Prism::ConstantReadNode then [nil, node.name]
        when Prism::ConstantPathNode, Prism::ConstantPathTargetNode
          [node.parent ? expr(node.parent) : :top, node.name]
        else refuse(node, "a dynamic constant path is not lowered yet")
        end
      end

      # The scope of a constant read and written by `A::B op= v`. A path
      # of constants reads the same twice; anything computed is held in a
      # hidden local, so the program sees it evaluated once.
      def constant_scope(node, line)
        scope, name = constant_path(node)
        return [scope, name, nil] if scope.nil? || scope == :top || constant_only?(scope)

        slot = temp(:scope)
        [read(slot, line), name, set(slot, scope, line)]
      end

      def with_scope(prelude, node, line)
        prelude ? Seq.new([prelude, node], line) : node
      end

      def constant_only?(scope)
        scope.is_a?(ConstRead) && (scope.scope.nil? || scope.scope == :top || constant_only?(scope.scope))
      end

      def define(node)
        @loader.loads_by_def!(node)
        marks = @body_marks
        receiver = node.receiver && expr(node.receiver)
        in_definee(nil, !receiver.nil?) do
          was = @in_def
          @in_def = true
          in_scope do
            params = parameters(node.parameters)
            @def_params = params
            body = node.body ? expr(node.body) : Literal.new(nil, node.location.start_line)
            body = marked(body, marks, node.location.start_line) unless marks.empty?
            locals = with_temps(node.locals + (params.names - node.locals))
            Def.new(node.name, params, locals, body, node.location.start_line, receiver, evals?(node.body), node.location.end_line,
                    method_cover(node))
          end
        ensure
          @in_def = was
        end
      end

      # The body with the `Primitive.attr!` rows of `marks` first, where a
      # def's own marks stand.
      def marked(body, marks, line)
        return Begin.new(*body.to_a).tap { |b| b.body = marked(body.body, marks, line) } if body.is_a?(Begin)

        rows = marks.map { |mark| Send.new(ConstRead.new(nil, :Primitive, line), :attr!, [Literal.new(mark, line)], line, false) }
        Seq.new([*rows, *(body.is_a?(Seq) ? body.stmts : [body])], line)
      end

      # Whether an eval stands anywhere in this body, blocks included
      # but nested defs left to themselves. A `return` an eval writes
      # belongs to the method the eval sits in, so that method arms the
      # catch for a signal that carries no home. Every spelling of eval
      # counts, since ruby gives them all that return: `instance_eval`,
      # `class_eval` and `module_eval` of a string, and a `send` or a
      # `method` that reaches one of them by name.
      def evals?(node)
        return false if node.nil? || node.is_a?(Prism::DefNode)
        return true if node.is_a?(Prism::CallNode) && eval_call?(node)

        node.child_nodes.any? { |child| evals?(child) }
      end

      # `Build.eval_call?` asked of a prism call, whose arguments are
      # still nodes: a leading Symbol literal is the name a send calls or
      # a fetch hands on.
      def eval_call?(node)
        args = node.arguments&.arguments || []
        named = args.first.unescaped.to_sym if args.first.is_a?(Prism::SymbolNode)
        Build.eval_call?(node.name, named: named, argc: args.size)
      end

      # The definee a body runs under: one step down the lexical path,
      # and whether it is the singleton side.
      # A `using` written in a body reaches the rest of that body and
      # nothing outside it.
      def in_definee(name, singleton)
        @path.push(name) if name
        was = @singleton
        using = @using
        marks = @body_marks
        @singleton = singleton
        @body_marks = []
        yield
      ensure
        @path.pop if name
        @singleton = was
        @using = using
        @body_marks = marks
      end

      # A bare `super`: the method's parameters passed on as they stand,
      # a `Super` with the locals of the def this block sits in.
      def zsuper(node, line)
        p = @def_params or return ZSuper.new(node.block && block(node.block), line)

        local = lambda do |name|
          name = name.whole if name.is_a?(MultiTarget)
          Local.new(name, @block_depth + (@def_depths ? @def_depths.fetch(name) : 0), line)
        end
        positional = (p.required + p.optional.map(&:first)).map(&local)
        positional << Splat.new(local.call(p.rest), line) if p.rest && p.rest != :implicit
        positional += p.post.map(&local)
        # The rest goes in first, which is the order ruby's own zsuper
        # builds the hash in.
        pairs = p.kwrest && p.kwrest != :nokey ? [HashSplat.new(local.call(p.kwrest), line), nil] : []
        pairs += p.keywords.flat_map { |name, _| [Literal.new(name, line), local.call(name)] }
        kwargs = pairs.empty? ? nil : HashLit.new(pairs, line)
        block = node.block ? block(node.block) : (p.block && BlockPass.new(local.call(p.block), line))
        Super.new(positional, kwargs, block, line, @block_depth.positive?)
      end

      # A ParametersNode as one Params.
      def parameters(node)
        return Params.new([], [], nil, [], [], nil, nil) if node.nil?

        required = node.requireds.map { |p| name_of(p) }
        optional = node.optionals.map { |p| [p.name, expr(p.value)] }
        rest = node.rest && rest_name(node.rest)
        post = node.posts.map { |p| name_of(p) }
        keywords = node.keywords.map do |k|
          case k
          when Prism::RequiredKeywordParameterNode then [k.name, nil]
          when Prism::OptionalKeywordParameterNode then [k.name, expr(k.value)]
          end
        end
        kwrest = node.keyword_rest && rest_name(node.keyword_rest)
        if node.keyword_rest.is_a?(Prism::ForwardingParameterNode)
          rest = ANONYMOUS[:rest]
          kwrest = ANONYMOUS[:kwrest]
          block = ANONYMOUS[:block]
        else
          block = node.block && (node.block.name || ANONYMOUS[:block])
        end
        Params.new(required, optional, rest, post, keywords, kwrest, block)
      end

      # A required parameter: its name, or a MultiTarget for `(a, b)`.
      # A bare super passes such an argument as it arrived, so the whole
      # of it is kept in a hidden local beside the names it takes apart.
      def name_of(param)
        return param.name unless param.is_a?(Prism::MultiTargetNode)

        target = multi_target(param)
        target.whole = temp(:arg)
        target
      end

      def multi_target(node)
        line = node.location.start_line
        rest = case node.rest
               when nil then nil
               when Prism::ImplicitRestNode then :implicit
               when Prism::SplatNode then node.rest.expression ? target(node.rest.expression) : :implicit
               else refuse(node.rest, "#{node.rest.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
               end
        MultiTarget.new(node.lefts.map { |t| target(t) }, rest, node.rights.map { |t| target(t) }, line)
      end

      # One target of a multiple assignment.
      def target(node)
        line = node.location.start_line
        case node
        when Prism::LocalVariableTargetNode, Prism::RequiredParameterNode then Assign.new(node.name, node.respond_to?(:depth) ? node.depth : 0, nil, line)
        when Prism::InstanceVariableTargetNode then IvarWrite.new(node.name, nil, line)
        when Prism::GlobalVariableTargetNode then gvar_write(node.name, nil, line)
        when Prism::ClassVariableTargetNode then CvarWrite.new(node.name, nil, line)
        when Prism::ConstantTargetNode then ConstWrite.new(nil, node.name, nil, line)
        when Prism::ConstantPathTargetNode
          scope, name = constant_path(node)
          ConstWrite.new(scope, name, nil, line)
        when Prism::MultiTargetNode then multi_target(node)
        when Prism::IndexTargetNode
          args = index_args(node, line)
          Send.new(expr(node.receiver), :[]=, args, line, false, args.none?(Splat), nil, nil)
        when Prism::CallTargetNode
          # `rescue => o&.x` and `for o&.x in list` write only when `o` is
          # not nil, as the safe call they spell does.
          Send.new(expr(node.receiver), node.name, [], line, false, false, nil, nil, node.call_operator == "&.")
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} as an assignment target is not lowered yet")
        end
      end

      # The indexes an index target names. A splat among them takes the
      # inline `[]` path away, since the count is only known at run time.
      def index_args(node, line)
        (node.arguments&.arguments || []).map { |a| a.is_a?(Prism::SplatNode) ? splat(a, line) : expr(a) }
      end

      # A rest parameter's name; `|a, |` has an implicit one that binds
      # nothing.
      def rest_name(node)
        case node
        when Prism::ImplicitRestNode then :implicit
        when Prism::RestParameterNode then node.name || ANONYMOUS[:rest]
        when Prism::KeywordRestParameterNode then node.name || ANONYMOUS[:kwrest]
        when Prism::ForwardingParameterNode then ANONYMOUS[:kwrest]
        when Prism::NoKeywordsParameterNode then :nokey
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
        end
      end

      # A block literal, or the `&value` a call passes on.
      def block(node)
        line = node.location.start_line
        return BlockPass.new(node.expression ? expr(node.expression) : Local.new(ANONYMOUS[:block], @block_depth, line), line) if node.is_a?(Prism::BlockArgumentNode)

        in_block do
          params, extra = block_params(node.parameters)
          body = node.body ? expr(node.body) : Literal.new(nil, line)
          noted(Block.new(params, with_temps(node.locals + extra + (params.names - node.locals - extra)), body, line,
                          node.location.end_line, method_cover(node)), node)
        end
      end

      # A block's Params and the locals prism leaves implicit: `it`, or
      # the numbered parameters.
      def block_params(node)
        none = Params.new([], [], nil, [], [], nil, nil)
        case node
        when nil then [none, []]
        when Prism::ItParametersNode then [Params.new([IT], [], nil, [], [], nil, nil), [IT]]
        when Prism::NumberedParametersNode
          names = (1..node.maximum).map { |i| :"_#{i}" }
          [Params.new(names, [], nil, [], [], nil, nil), []]
        when Prism::BlockParametersNode
          # A block-local (`|x; y|`) is already among the block's locals,
          # where prism resolves it at depth 0, fresh each call.
          [parameters(node.parameters), []]
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
        end
      end

      REQUIRES = %i[require require_relative load].freeze

      # Whether the definee this call stands in has a `require` or
      # `load` of its own, which dispatch reaches before Kernel's.
      def shadowed?(name) = @shadowed.key?([@path.join("::"), @singleton, name])

      def call(node)
        mark = body_mark(node)
        @body_marks |= [mark] if mark
        return Not.new(expr(node.receiver), node.location.start_line) if node.name == :! && node.receiver && node.arguments.nil? && node.call_operator != "&."
        return FrozenString.new(unescaped(node.receiver), node.location.start_line) if node.name == :freeze && node.receiver.is_a?(Prism::StringNode) && node.arguments.nil? && node.block.nil?
        # The core's `+"text"` under its frozen_string_literal comment: a
        # fresh String, as its C makes one, with no send of +@.
        return Literal.new(unescaped(node.receiver), node.location.start_line, false) if node.name == :+@ && node.receiver.is_a?(Prism::StringNode) && node.block.nil? && Build.runtime_file?(@file)
        return require_node(node) if REQUIRES.include?(node.name) && node.receiver.nil? && node.block.nil? && !shadowed?(node.name) && !@loader&.eval? && literal_feature(node)
        return autoload_node(node) if node.name == :autoload && node.block.nil? && literal_autoload?(node)

        send = plain_call(node)
        relative_in_file(node, send)
      end

      # A file of the program names rubygems' API; rubygems' own files and
      # the runtime's do not count.
      def gems!(name)
        @loader.gems!(name) if @loader && !@loader.ahead?(@file) && !Build.runtime_file?(@file)
      end

      # `Primitive.attr! :ruby`, `:hidden` or `:ivars` standing in a class
      # body of the core library: every def after it in that body takes the
      # mark, as though each began with it. `:ruby` marks methods CRuby
      # writes in Ruby; `:hidden` a class of helpers CRuby writes as a C
      # struct; `:ivars` a class whose instance variables CRuby shows.
      def body_mark(node)
        mark = node.arguments&.arguments&.first
        return unless !@in_def && node.name == :attr! && node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Primitive &&
                      mark.is_a?(Prism::SymbolNode) && %w[ruby hidden ivars].include?(mark.unescaped)

        mark.unescaped.to_sym
      end

      # A string compiled while the program runs from a file that has a
      # place, `load`ed or given one by an eval, keeps its literal
      # require_relative a send; the name it passes is spelled from that
      # file's directory, which the frame of runtime Ruby cannot tell.
      def relative_in_file(node, send)
        return send unless @loader&.eval? && node.name == :require_relative && node.receiver.nil? && File.absolute_path?(@file)

        feature = literal_feature(node)
        return send unless feature

        send.args = [Literal.new(File.expand_path(feature, File.dirname(@file)), send.line)]
        send
      end

      # A call as the Send it is, with none of the forms above: what
      # `defined?` asks about, since it never runs the call. `compiles`
      # is false for a require of a literal name that no root holds: the
      # call searches when it runs, and finds a file the program was not
      # compiled with only where the program changed $LOAD_PATH, which
      # brings the compiler along by itself.
      def plain_call(node, compiles: true)
        args, kwargs, forwarded = arguments(node.arguments)
        kernel = compiles && (node.receiver.nil? || (node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Kernel))
        @loader.evals!(node.name, args, kernel: kernel)
        gems!(:Gem) if node.name == :gem && node.receiver.nil?
        @loader.load_path_changed!(node, @file)
        @loader.normalizes!(node.name, args)
        # `&:name` calls the method it names, as a call of that name does.
        if node.block.is_a?(Prism::BlockArgumentNode) && node.block.expression.is_a?(Prism::SymbolNode)
          @loader.normalizes!(node.block.expression.unescaped.to_sym, [])
        end
        # The inline `[]`, `[]=` and `<<` check visibility as an explicit
        # call does, so a literal `self` dispatches, private methods and all.
        # A named call with a fast path (OPT_CALLS) is one on an explicit
        # receiver, plain, with the arguments the body takes.
        opt = ((%i[[] []=].include?(node.name) && node.opening == "[") ||
               (node.name == :<< && node.call_operator.nil? && args.size == 1) ||
               (OPT_CALLS[node.name] == args.size && node.call_operator == "." && kwargs.nil? && node.block.nil? && forwarded.nil? &&
                args.none?(Splat))) &&
              !node.receiver.is_a?(Prism::SelfNode)
        recv = node.receiver && expr(node.receiver)
        # A refinement is in use inside its own block, so a sibling
        # refined method is reachable there by bare name.
        blk = node.block ? in_refine(node.name) { block(node.block) } : forwarded
        safe = node.call_operator == "&."
        # Both sides of a safe call stand where the call does, which is
        # what CRuby records for one. `branch_covers` answers a row of
        # nils where nothing is measured, and a Send carries none.
        covers = safe ? branch_covers(:"&.", span(node.location), [[:then, span(node.location)], [:else, span(node.location)]]) : nil
        Send.new(recv, node.name, args, message_line(node), node.variable_call?, opt,
                 blk, kwargs, safe, node.attribute_write?, nil, covers&.first && covers)
      end

      def in_refine(name)
        return yield unless name == :refine

        was = @using
        @using = :owner
        begin
          yield
        ensure
          @using = was
        end
      end

      # A call stands where its name does, which a receiver spread over
      # several lines is not.
      def message_line(node) = node.message_loc&.start_line || node.location.start_line

      # The name a require names at compile time: a String literal, or a
      # path built from `__dir__` with a literal.
      def literal_feature(node)
        args = node.arguments&.arguments
        return nil unless args&.size == 1

        args[0].is_a?(Prism::StringNode) ? args[0].unescaped : @loader.literal_path(args[0], @file)
      end

      # A require of a literal name resolves now: the file becomes a unit
      # of the program. A name ruby itself answers but no root here holds
      # stops by name; every other name raises LoadError when it runs, as
      # it does in ruby.
      # The features ruby loads before a program starts, so a require of
      # one answers false.
      # The runtime's gem prelude loads error_highlight, did_you_mean and
      # syntax_suggest's core extension, as ruby's does. ruby 4.0.6 also
      # loads rubygems, which this runtime does not carry: a require of it
      # stops by name rather than answering false and failing at the first
      # use. Only pathname's C half is loaded, so `require "pathname"`
      # still runs its Ruby half and answers true.
      GEM_PRELOADED = %w[error_highlight did_you_mean syntax_suggest/core_ext].freeze
      PRELOADED = (%w[enumerator thread fiber rational complex ruby2_keywords set monitor rbconfig] + GEM_PRELOADED).freeze

      # The features ruby carries that no library root here holds, and
      # that ruby did not load before the program: a require of one stops
      # by name.
      def self.missing_features(target = Target.default)
        (@missing_features ||= {})[target.triple] ||= FEATURES.reject do |feature|
          PRELOADED.include?(feature) || stdlib(target).any? { |root| File.file?(File.join(root, "#{feature}.rb")) }
        end.sort.freeze
      end

      # A feature ruby loaded before the program, by any of its names:
      # `thread`, `thread.rb` and `enumerator.so` all count.
      def preloaded?(feature)
        (@loader ? @loader.preloaded : PRELOADED).include?(feature.to_s.sub(/\.(?:rb|so|bundle)\z/, ""))
      end

      def require_node(node)
        line = node.location.start_line
        feature = literal_feature(node)
        if node.name == :require && %w[rubygems bundled_gems].include?(feature.to_s.delete_suffix(".rb")) && !@loader.ahead?(@file) && !Build.runtime_file?(@file)
          # The prelude loaded rubygems as the program booted.
          gems!(:Gem)
          return Literal.new(false, line)
        end
        if node.name == :require && preloaded?(feature)
          @loader.configures! if feature.to_s.delete_suffix(".rb") == "rbconfig"
          return Literal.new(false, line)
        end

        return plain_call(node, compiles: false) if @loader.deferred?(feature) || (@in_def && @loader.ahead?(@file))

        path = @loader.resolve(node.name, feature, @file)
        stop = path.nil? && node.name != :require_relative && stop_for(node, feature)
        return stop if stop

        # No file here yet: the call looks for one when it runs, under the
        # $LOAD_PATH the program has built by then. The build never asks
        # the host's rubygems for a gem that holds the feature: what a
        # binary carries is what zr vendors and what the program's own
        # roots hold, so the same source builds the same bytes on any
        # machine.
        return plain_call(node, compiles: false) unless path

        # A require made while a file only the eval road loads runs is the
        # compiler's own; the runtime knows that as it runs, so one unit
        # serves the road and a program that requires the file itself.
        Require.new(node.name, feature, path, @loader.add(path), line)
      end

      # Why a name ruby carries is not here, where the answer is a
      # decision and not a gap. The stop reads "<reason> is not
      # implemented yet" (`zr_unloadable`), so each of these finishes
      # that sentence.
      UNSUPPORTED_LIBRARIES = {
        "mkmf" => "mkmf, which writes a C extension's Makefile: zr compiles no C, so an extension it configured",
        "prism/ffi" => "prism/ffi, the FFI half of prism: this runtime's prism is a Ruby port of the C, so the C half"
      }.freeze

      # A feature ruby carries, which this runtime has no file for. The
      # stop waits until the program runs the require: a guarded one that
      # the program never reaches costs it nothing.
      def stop_for(node, feature)
        name = feature.to_s.delete_suffix(".rb")
        return unless FEATURES.include?(name)

        line = node.location.start_line
        Stop.new(UNSUPPORTED_LIBRARIES[name] || "#{node.name} of #{feature.inspect}", line)
      end

      # An autoload that registers nothing and answers nil, which is what
      # ruby's does for a feature it already holds. The receiver still
      # runs: `whatever.autoload :X, "set"` calls `whatever` before it
      # finds there is nothing to do.
      def nothing(node, line)
        recv = node.receiver && expr(node.receiver)
        recv ? Seq.new([recv, Literal.new(nil, line)], line) : Literal.new(nil, line)
      end

      def literal_autoload?(node)
        args = node.arguments&.arguments
        args&.size == 2 && args[0].is_a?(Prism::SymbolNode) && (args[1].is_a?(Prism::StringNode) || @loader.literal_path(args[1], @file))
      end

      # `autoload :Name, "feature"` resolves the feature as a require
      # would, so the file is a unit of the program.
      def autoload_node(node)
        line = node.location.start_line
        name_node, path_node = node.arguments.arguments
        feature = path_node.is_a?(Prism::StringNode) ? path_node.unescaped : @loader.literal_path(path_node, @file)
        # A feature the program already holds keeps no row, as in ruby:
        # `require` would answer false and read no file, so
        # `Object.autoload?(:Set)` is nil after `autoload :Set, "set"`.
        # The name is still declared, and that is visible on any module
        # but Object -- `M.constants` names it, and the constant stands
        # undefined there rather than reading one further out.
        #
        # No row also means the loader never believes a file must be
        # found while the program runs, which is the one thing that needs
        # the compiler: `autoload :Set, "set"` would otherwise add the
        # whole of it -- 44 MB -- for a declaration that reads nothing.
        return Autoload.new(node.receiver && expr(node.receiver), name_node.unescaped.to_sym, feature, feature, nil, line,
                            true) if preloaded?(feature)

        path = @loader.resolve(:require, feature, @file)
        # An autoload the gem prelude's boot does not read leaves its file
        # to the program that reads the constant.
        return Autoload.new(node.receiver && expr(node.receiver), name_node.unescaped.to_sym, path || feature, path || feature, nil, line) if path && @loader.ahead?(@file) && !@loader.booted?(path)

        stop = path.nil? && stop_for(node, feature)
        unit = stop ? @loader.stop_unit(stop.what, line) : (path && @loader.add(path))
        # No root holds the file: the first read requires the feature
        # under the $LOAD_PATH the program has built by then.
        @loader.compiles_at_run_time! unless unit
        Autoload.new(node.receiver && expr(node.receiver), name_node.unescaped.to_sym, feature, path || feature, unit, line)
      end

      # `defined?(value)`: the form decides at compile time; only an
      # ivar, gvar, cvar, constant, method, yield or super asks at run time.
      # The globals ruby always has, whose `defined?` is "global-variable"
      # whether or not they hold a value (CRuby's hooked variables).
      SPECIAL_GVARS = %i[$! $@ $~ $_ $; $, $/ $\\ $0 $* $$ $? $: $" $< $> $. $stdin $stdout $stderr
                         $VERBOSE $DEBUG $FILENAME $LOAD_PATH $LOADED_FEATURES $PROGRAM_NAME].freeze

      # CRuby's defined_expr0: what each form answers, and which forms ask
      # at run time.
      def defined(node, line)
        case node
        when Prism::LocalVariableReadNode, Prism::ItLocalVariableReadNode then Defined.new(:local, nil, line)
        when Prism::InstanceVariableReadNode then Defined.new(:ivar, node.name, line)
        when Prism::GlobalVariableReadNode
          if SPECIAL_GVARS.include?(gvar_name(node.name)) || @loader&.back_ref(node.name)
            Defined.new(:global, nil, line)
          else
            Defined.new(:gvar, node.name, line)
          end
        # `$1` and `$&` name a part of the last match: defined while it has one.
        when Prism::NumberedReferenceReadNode, Prism::BackReferenceReadNode then Defined.new(:backref, expr(node), line)
        when Prism::ClassVariableReadNode then Defined.new(:cvar, node.name, line)
        when Prism::ConstantReadNode, Prism::ConstantPathNode then Defined.new(:const, expr(node), line)
        when Prism::CallNode
          # `o.x = v` and `o[k] = v` are assignments while `o` has the writer.
          if node.attribute_write? then Defined.new(:attrasgn, plain_call(node), line)
          # A call with a block literal is an expression, whatever it calls.
          elsif node.block.is_a?(Prism::BlockNode) then Defined.new(:expression, nil, line)
          else Defined.new(:method, plain_call(node), line)
          end
        when Prism::YieldNode then Defined.new(:yield, nil, line)
        when Prism::SuperNode, Prism::ForwardingSuperNode then Defined.new(:super, nil, line)
        # An Array or Hash literal is defined when every part is.
        when Prism::ArrayNode
          node.elements.any?(Prism::SplatNode) ? Defined.new(:expression, nil, line) : Defined.new(:list, node.elements.map { |e| expr(e) }, line)
        when Prism::HashNode then Defined.new(:list, [HashLit.new(hash_pairs(node.elements), line)], line)
        # `(x)` asks about `x`, and `()` or an empty `begin` is nil.
        when Prism::ParenthesesNode
          return Defined.new(:nil, nil, line) if node.body.nil?

          inner = node.body.is_a?(Prism::StatementsNode) && node.body.body.size == 1 ? node.body.body.first : nil
          inner ? defined(inner, line) : Defined.new(:expression, nil, line)
        when Prism::BeginNode
          empty = node.statements.nil? && node.rescue_clause.nil? && node.else_clause.nil? && node.ensure_clause.nil?
          Defined.new(empty ? :nil : :expression, nil, line)
        when Prism::SelfNode then Defined.new(:self, nil, line)
        when Prism::NilNode then Defined.new(:nil, nil, line)
        when Prism::TrueNode then Defined.new(:true, nil, line)
        when Prism::FalseNode then Defined.new(:false, nil, line)
        else Defined.new(assignment?(node) ? :assignment : :expression, nil, line)
        end
      end

      # Every form that writes a variable, a constant, an attribute or an
      # index, an operator assignment among them; a named-capture match
      # is a call.
      def assignment?(node) = node.class.name.end_with?("WriteNode") && !node.is_a?(Prism::MatchWriteNode)

      # `for x in list; body; end` is `list.each { |x| body }` with the
      # body in the enclosing scope: its locals move one scope out.
      def for_loop(node)
        line = node.location.start_line
        target = deepen(target(node.index), 0)
        body = node.statements ? deepen(seq(node.statements), 0) : Literal.new(nil, line)
        value = Local.new(:"*for", 0, line)
        if target.is_a?(MultiTarget)
          # `for a, b in o` takes every value yielded, as `|a, b|` does:
          # the block collects them, and one alone stands for itself.
          got = Local.new(:"*for", 0, line)
          one = Send.new(Send.new(got, :size, [], line, false, false, nil, nil, false, false), :==, [Literal.new(1, line)], line, false, false, nil, nil, false, false)
          first = Send.new(got, :[], [Literal.new(0, line)], line, false, false, nil, nil, false, false)
          bind = MultiAssign.new(target, If.new(one, first, got, line), line)
          params = Params.new([], [], :"*for", [], [], nil, nil)
        else
          bind = target.is_a?(Send) ? target.tap { |t| t.args << value } : target.tap { |t| t.value = value }
          params = Params.new([:"*for"], [], nil, [], [], nil, nil)
        end
        block = Block.new(params, [:"*for"], Seq.new([bind, body], line), line)
        Send.new(expr(node.collection), :each, [], line, false, false, block, nil, false)
      end

      # `node` as it reads one block scope deeper: every local that
      # reaches `level` or beyond is one further out.
      def deepen(node, level)
        case node
        when Local, Assign
          node.depth += 1 if node.depth >= level
          node.value = deepen(node.value, level) if node.is_a?(Assign) && node.value
          node
        when Block
          node.body = deepen(node.body, level + 1)
          node.params.optional.each { |pair| pair[1] = deepen(pair[1], level + 1) }
          node.params.keywords.each { |pair| pair[1] = deepen(pair[1], level + 1) if pair[1] }
          node
        when Def
          node.receiver = deepen(node.receiver, level) if node.receiver
          node
        when ClassDef
          node.scope = deepen(node.scope, level) if node.scope.is_a?(Record)
          node.superclass = deepen(node.superclass, level) if node.superclass
          node
        when ModuleDef
          node.scope = deepen(node.scope, level) if node.scope.is_a?(Record)
          node
        when SingletonClassDef
          node.target = deepen(node.target, level)
          node
        when Record
          node.each_pair { |k, v| node[k] = deepen(v, level) if v.is_a?(Record) || v.is_a?(Array) }
          node
        when Array then node.map! { |v| v.is_a?(Record) || v.is_a?(Array) ? deepen(v, level) : v }
        else node
        end
      end

      # `[args, kwargs, block]` of an argument list: Splats among the
      # args, the keywords as one HashLit or nil, and the block `...`
      # forwards, or nil.
      def arguments(node)
        kwargs = nil
        block = nil
        args = (node&.arguments || []).filter_map do |a|
          line = a.location.start_line
          case a
          when Prism::SplatNode then splat(a, line)
          when Prism::KeywordHashNode
            kwargs = HashLit.new(hash_pairs(a.elements), line)
            nil
          when Prism::ForwardingArgumentsNode
            kwargs = HashLit.new([HashSplat.new(Local.new(ANONYMOUS[:kwrest], @block_depth, line), line), nil], line)
            block = BlockPass.new(Local.new(ANONYMOUS[:block], @block_depth, line), line)
            Splat.new(Local.new(ANONYMOUS[:rest], @block_depth, line), line)
          else expr(a)
          end
        end
        [args, kwargs, block]
      end

      # A string literal as prism flags it: frozen where the file's magic
      # comment says so, by CRuby's own reading of the comment, and then
      # the one frozen String of its text, as CRuby interns it.
      def literal_string(node, text, line) = node.frozen? ? frozen_literal_string(text, line) : Literal.new(text, line, !node.mutable?)

      # A literal a frozen_string_literal comment freezes: the one frozen
      # String of its text, with no send of `freeze`, which ruby never
      # sends for one.
      def frozen_literal_string(text, line) = FrozenString.new(text, line, text.encoding == ::Encoding::UTF_8)

      # The text of a string prism found static (`"a" "b"`, a heredoc with
      # no interpolation): its parts joined.
      def static_string?(node)
        node.parts.all? { |part| part.is_a?(Prism::StringNode) || (part.is_a?(Prism::InterpolatedStringNode) && static_string?(part)) }
      end

      def static_text(node) = node.parts.map { |part| part.is_a?(Prism::StringNode) ? unescaped(part) : static_text(part) }.join

      # A string part's text as ruby tags it: a \u escape makes it UTF-8,
      # and a \x escape past ASCII in a US-ASCII file makes it binary,
      # whatever the file's own encoding. Prism flags both but hands the
      # text over in the file's encoding.
      def unescaped(node)
        text = node.unescaped
        if node.forced_utf8_encoding? then text.dup.force_encoding(Encoding::UTF_8)
        elsif node.forced_binary_encoding? then text.dup.force_encoding(Encoding::BINARY)
        else text
        end
      end

      # An element of an array literal. `[1, a: 2]` holds a Hash; keywords
      # made only of `**` splats add it only when it is not empty.
      def array_element(node, line)
        case node
        when Prism::SplatNode then splat(node, line)
        when Prism::KeywordHashNode
          hash = HashLit.new(hash_pairs(node.elements), line)
          node.elements.all?(Prism::AssocSplatNode) ? Splat.new(KwSplatElement.new(hash, line), line) : hash
        else expr(node)
        end
      end

      # `*value`, or a bare `*`: the anonymous rest parameter the method
      # forwards, wherever a splat can stand.
      def splat(node, line)
        Splat.new(node.expression ? expr(node.expression) : Local.new(ANONYMOUS[:rest], @block_depth, line), line)
      end

      # A hash's elements as a flat pair list; a `**value` is a HashSplat
      # key with a nil value.
      def hash_pairs(elements)
        elements.flat_map do |e|
          case e
          when Prism::AssocNode
            [expr(e.key), expr(e.value.is_a?(Prism::ImplicitNode) ? e.value.value : e.value)]
          when Prism::AssocSplatNode
            [HashSplat.new(e.value ? expr(e.value) : Local.new(ANONYMOUS[:kwrest], @block_depth, e.location.start_line), e.location.start_line), nil]
          end
        end
      end

      # The bodies a file runs whenever it loads: its own statements, a
      # class or a module body, and a `begin` that stands for grouping.
      # A branch, a loop, a block and a method body are none of these.
      def self.always_run(node)
        case node
        when Prism::ProgramNode, Prism::BeginNode then [node.statements]
        when Prism::StatementsNode then node.body
        when Prism::ModuleNode, Prism::ClassNode, Prism::SingletonClassNode then [node.body]
        end
      end

      # Every `alias $x $&` the file always runs, by identity.
      def self.certain_aliases(node, out = {}.compare_by_identity)
        (always_run(node) || []).compact.each do |child|
          out[child] = true if child.is_a?(Prism::AliasGlobalVariableNode)
          certain_aliases(child, out)
        end
        out
      end

      # Whether this file always runs `node`. The walk happens the first
      # time one is asked about, which for almost every file is never.
      def certain_alias?(node)
        return true unless @root

        (@certain ||= Build.certain_aliases(@root)).key?(node)
      end

      def refuse(node, message)
        raise Refused, "#{@file}:#{node.location.start_line}: #{message}"
      end

      # A refusal of a form ruby refuses too, which a program compiling
      # it while it runs sees as the SyntaxError ruby raises.
      def invalid(node, message)
        raise Invalid, "#{@file}:#{node.location.start_line}: #{message}"
      end
    end
  end
end
