# frozen_string_literal: true

module Zr
  module Hir
    class Build
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
        # `gem_set` is the build's GemSet (lib/zr/gem_set.rb), whose roots
        # come first in `roots`, or nil.
        def initialize(roots, eval: false, external: nil, trace: false, evals: false, covers: false, activations: nil,
                       deferred: [], preloaded: PRELOADED, ahead: Build.ahead, booted: Build.booted, prebuilt_eval: nil, gem_set: nil)
          @deferred = deferred
          @gem_set = gem_set
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

        # A program's method that replaces one of these and calls `super`
        # passes a name to Kernel's or Module's method that no site shows.
        def loads_by_def!(node)
          return unless (REQUIRES.include?(node.name) || node.name == :autoload) && node.body

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
            @evals = true if kernel && REQUIRES.include?(named)
            return
          end
          @evals = true if kernel && REQUIRES.include?(name)
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

        # The script encoding that `__ENCODING__` answers. Prism's
        # result gives the source String's own encoding when the text is
        # not ASCII, so the magic comment is read again here, where ruby
        # reads it: line 1, or line 2 after a shebang.
        def source_encoding(result, source)
          lines = source.b.lines.first(2)
          lines = lines.first(1) unless lines.first&.start_with?("#!")
          name = lines.filter_map { |line| line[/\A\s*#.*?coding[:=][ \t]*([\w.-]+)/i, 1] }.first
          return result.encoding unless name

          ::Encoding.find(name)
        rescue ArgumentError
          result.encoding
        end

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
          build = Build.new(file, self, source_encoding(result, source), shadowed: shadowed(result.value), root: result.value,
                                                                         eval: !scopes.nil?)
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

          message = yields.map { |e| "#{file}:#{e.location.start_line}: #{e.message}" }.join("\n")
          Hir.syntax_error(message, file).tap { |exc| exc.set_backtrace([file]) }
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

        # Why a build cannot use the file at `path`: it is in a gem of the
        # GemSet that zr cannot compile (a C extension). Nil otherwise.
        def refused_gem(path, feature = nil) = @gem_set&.refusal(path, feature)

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
    end
  end
end
