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
        # @rbs @deferred: Array[String]
        # @rbs @modules: Hash[String, bool]
        # @rbs @description: (^() -> String?)?
        # @rbs @gem_set: GemSet?
        # @rbs @gate: bool | Symbol
        # @rbs @own: Hash[String, bool]
        # @rbs @main: String?
        # @rbs @data: Hash[String, Integer]
        # @rbs @prebuilt_eval: untyped
        # @rbs @preloaded: Array[String]
        # @rbs @ahead: Array[String]
        # @rbs @booted: Array[String]
        # @rbs @gems: bool
        # @rbs @native_gems: Array[GemSet::Entry]
        # @rbs @eval: bool
        # @rbs @trace: bool
        # @rbs @traces: bool
        # @rbs @covers: bool
        # @rbs @coverable: Hash[String, [Integer, Array[Integer]]]
        # @rbs @branches: Hash[String, Array[Array[Symbol | Integer | nil]]]
        # @rbs @branch_count: Integer
        # @rbs @defs: Hash[String, Array[Array[Integer]]]
        # @rbs @def_count: Integer
        # @rbs @roots: Array[String]
        # @rbs @units: Array[Unit]
        # @rbs @stopped: Array[String]
        # @rbs @index: Hash[String, entry]
        # @rbs @evals: bool
        # @rbs @normalizes: bool
        # @rbs @pretty_prints: bool
        # @rbs @irbs: bool
        # @rbs @load_path_computed: bool?
        # @rbs @real_roots: Hash[String, String]?
        # @rbs @asts: bool
        # @rbs @configures: bool
        # @rbs @activations: Integer
        # @rbs @back_refs: Hash[Symbol, Prism::node]
        # @rbs @alias_flags: Hash[Symbol, Symbol?]
        # @rbs @hiding: bool?
        # @rbs @switches: Switches

        attr_reader :units #: Array[Unit]

        # The ruby features that a require or an autoload stopped on,
        # because no root has the file (`Build#stop_for`).
        attr_reader :stopped #: Array[String]

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
        # `gate`: a literal require in the program's own files that no
        # root has stops the build (`Build#gate!`). A build from the CLI
        # sets it; `--allow-runtime-require` does not.
        # `switches` are the ruby switches of the build (`Hir::Switches`).
        # @rbs roots: Array[String]
        # @rbs eval: bool
        # @rbs external: untyped
        # @rbs trace: bool
        # @rbs evals: bool
        # @rbs covers: bool
        # @rbs activations: Integer?
        # @rbs deferred: Array[String]
        # @rbs preloaded: Array[String]
        # @rbs ahead: Array[String]
        # @rbs booted: Array[String]
        # @rbs prebuilt_eval: untyped
        # @rbs gem_set: GemSet?
        # @rbs gate: bool | Symbol
        # @rbs description: (^() -> String?)?
        # @rbs switches: Switches
        # @rbs def_base: Integer
        # @rbs return: void
        def initialize(roots, eval: false, external: nil, trace: false, evals: false, covers: false, activations: nil,
                       deferred: [], preloaded: PRELOADED, ahead: Build.ahead, booted: Build.booted, prebuilt_eval: nil, gem_set: nil,
                       gate: false, description: nil, switches: Switches::NONE, def_base: 0)
          @deferred = deferred
          @switches = switches
          @modules = {}
          @description = description
          @gem_set = gem_set
          @gate = gate
          @own = {}
          @main = nil
          @data = {}
          @prebuilt_eval = external ? nil : prebuilt_eval
          @preloaded = preloaded
          @ahead = ahead
          @booted = booted
          @gems = false
          @native_gems = [] #: Array[GemSet::Entry]
          @eval = eval
          @trace = trace
          @traces = false
          @covers = covers
          @coverable = {}
          @branches = {}
          @branch_count = 0
          @defs = {}
          @def_count = def_base
          @roots = roots.map { |r| File.expand_path(r) }
          @units = []
          @stopped = []
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
        #: (Symbol name) -> Prism::node?
        def back_ref(name) = @back_refs[name]

        # Whether a file uses TracePoint or set_trace_func, and whether
        # this build fires the events that a TracePoint listens for.
        #: () -> bool
        def traces? = @traces
        #: () -> bool
        def tracing? = @trace

        # The names in a program that wants `:line` events. The source
        # bytes are checked first, because almost no file contains these
        # words, and a regexp is much faster than a tree walk. If a file
        # contains one, the tree is walked, so a word in a comment does
        # not arm the events for every statement and cause a second build.
        # An allocation trace also needs the line of each statement, and
        # the frame of each core method, which an inline iterator has not.
        TRACE_NAMES = /\b(?:TracePoint|set_trace_func|add_trace_func|Coverage|trace_object_allocations\w*)\b/
        TRACE_CONSTANTS = %i[TracePoint Coverage].freeze
        TRACE_CALLS = %i[set_trace_func add_trace_func trace_object_allocations trace_object_allocations_start].freeze
        COVERAGE_CONSTANTS = %i[Coverage].freeze

        #: (Prism::node tree) -> bool
        def names_tracing?(tree) = names_of?(tree, TRACE_CONSTANTS, TRACE_CALLS)

        #: (Prism::node tree) -> bool
        def names_coverage?(tree) = names_of?(tree, COVERAGE_CONSTANTS, [])

        # Whether the tree's code uses one of `constants` or calls one of
        # `calls`. A string or a symbol does not count: a help text or a
        # table of these names (as in this file) is not a trace, and the
        # events cost code size and time in every file. A program that
        # reaches TracePoint only by a name in a string, a symbol or an
        # eval's code is built with `--trace` (or `ZR_TRACE=1`); without
        # it, the TracePoint warns when it is enabled.
        #: (Prism::node tree, Array[Symbol] constants, Array[Symbol] calls) -> bool
        def names_of?(tree, constants, calls)
          !tree.breadth_first_search do |n|
            case n
            when Prism::ConstantReadNode then constants.include?(n.name)
            when Prism::ConstantPathNode then n.parent.nil? && constants.include?(n.name)
            when Prism::CallNode then calls.include?(n.name)
            end #: bool
          end.nil?
        end

        # Whether a file uses Coverage. Also, for each file, its line count
        # and the lines where a traced build fires :line events. Coverage
        # returns nil for the other lines and counts these.
        #: () -> bool
        def covers? = @covers
        COVERAGE_NAMES = /\bCoverage\b/
        attr_reader :coverable #: Hash[String, [Integer, Array[Integer]]]

        #: (String file, Integer line) -> void
        def line_event!(file, line)
          @coverable[file]&.last&.push(line)
        end

        # The branch records of each measured file, in Coverage's order: a
        # root, then its branches, then the next root.
        attr_reader :branches #: Hash[String, Array[Array[Symbol | Integer | nil]]]

        # Adds a record for branch `kind` over `span`, and returns
        # `[id, index]`. `id` is its `Cover` id, unique in the program,
        # because one counter array contains all files' counters. `index`
        # is the record's position in its file: Coverage shows it, and a
        # branch refers to its root by it. `under` is the root's index for
        # a branch, nil for a root.
        #: (String file, Symbol kind, Array[Integer] span, ?under: Integer?) -> [Integer, Integer]
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
        attr_reader :defs #: Hash[String, Array[Array[Integer]]]

        #: (String file, Array[Integer] span) -> Integer
        def def_site!(file, span)
          id = @def_count
          @def_count += 1
          (@defs[file] ||= []) << [id, *span]
          id
        end

        # The number of `using` entries in use after this build, and the
        # next entry that it takes.
        attr_reader :activations #: Integer

        # The `using` entry in force where an eval runs, which its code
        # starts under, or nil.
        attr_accessor :eval_using #: Integer?
        # The `using` entry in force at the end of an eval's toplevel.
        attr_reader :eval_using_after #: Integer?

        #: () -> Integer
        def next_activation = @activations.tap { @activations += 1 }

        # `flag` is the global that a conditional alias sets when it runs,
        # or nil for an alias that always runs.
        #: (Symbol new_name, Prism::node old_name, ?Symbol? flag) -> void
        def back_ref!(new_name, old_name, flag = nil)
          @back_refs[new_name] = old_name
          @alias_flags[new_name] = flag
        end

        #: (Symbol name) -> Symbol?
        def alias_flag(name) = @alias_flags[name]

        #: () -> bool
        def evals? = @evals

        #: (String? feature) -> bool
        def deferred?(feature) = @deferred.include?(feature)

        #: (String file) -> bool
        def ahead?(file) = @ahead.any? { |dir| file.start_with?(dir) }

        #: (String path) -> bool
        def booted?(path) = @booted.include?(path)

        attr_reader :preloaded #: Array[String]

        # A file that the program requires but that only run time can find.
        #: () -> void
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
        #: (Prism::CallNode node, String file) -> void
        def load_path_changed!(node, file)
          return unless node.receiver.is_a?(Prism::GlobalVariableReadNode) && %i[$LOAD_PATH $:].include?(node.receiver.name)
          return unless LOAD_PATH_CHANGES.include?(node.name)

          literal = %i[unshift push <<].include?(node.name) && node.arguments&.arguments&.all? { |a| literal_path(a, file) }
          return if literal

          @evals = true
          @load_path_computed = true
        end

        # Whether a file changed $LOAD_PATH in a way the compiler cannot
        # follow. A later require of a library name then searches the
        # path at run time, as ruby does, and finds the compiled file only
        # when no directory the program added has one of that name.
        #: () -> bool
        def load_path_computed? = @load_path_computed || false

        # Whether this build is an eval. A string of ruby cannot add a unit
        # to a program that is already linked, and it cannot see the
        # methods of its enclosing class. So `require` and `load` there are
        # normal sends, and dispatch decides.
        #: () -> bool
        def eval? = @eval

        # Each file that this loader reached, by path: its unit's index, or
        # its entry in an external EvalSupport.
        #: () -> Hash[String, entry]
        def entries = @index

        # The unit at `path` and all that it loads, built as eval support
        # files (hidden).
        #: (String path) -> entry
        def hidden(path)
          @hiding = true
          add(path)
        ensure
          @hiding = false
        end

        # A program's method that replaces one of these and calls `super`
        # passes a name to Kernel's or Module's method that no site shows.
        #: (Prism::DefNode node) -> void
        def loads_by_def!(node)
          return unless (REQUIRES.include?(node.name) || node.name == :autoload) && node.body

          supers = node.body.breadth_first_search { |n| n.is_a?(Prism::SuperNode) || n.is_a?(Prism::ForwardingSuperNode) }
          @evals = true if supers
        end

        # `kernel` tells that the call goes to Kernel's method: it has no
        # receiver, or `Kernel` is the receiver. `YAML.load` does not. An
        # `autoload` that gets here has a computed feature, with any
        # receiver, because Module#autoload also takes one.
        #: (Symbol name, Array[untyped] args, ?kernel: bool) -> void
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

        #: (Symbol name, Array[node] args) -> bool
        def ruby_command?(name, args)
          return false unless COMMANDS.include?(name)

          command = args[1]
          command.is_a?(Interp) || (command.is_a?(Literal) && command.value.is_a?(String) && !(name == :trap && TRAP_WORDS.include?(command.value)))
        end

        # A program that uses Ruby::Box or RubyVM::InstructionSequence
        # compiles ruby at run time: all code in a box, and every string
        # that an instruction sequence compiles, goes through the compiler.
        COMPILES = %i[Ruby InstructionSequence].freeze

        # The classes and modules that the program's files define, by
        # lexical name (`Prism::Ruby`). A bare `Ruby` inside `module Prism`
        # is Prism's own module then, not Ruby::Box.
        #: (Array[String?] path, String name) -> bool
        def module_defined!(path, name) = @modules[[*path, name].join("::")] = true

        # Whether `name`, read in the lexical `path`, names a class or
        # module that a file defines inside that path.
        #: (Array[String?] path, Symbol name) -> bool
        def module_defined?(path, name) = path.size.downto(1).any? { |n| @modules.key?([*path.first(n), name].join("::")) }

        #: (Symbol name) -> void
        def compiles!(name)
          @evals = true if COMPILES.include?(name)
          @asts = true if name == :AbstractSyntaxTree
        end

        # Whether a file uses RubyVM::AbstractSyntaxTree. The translator
        # builds its trees from prism.
        #: () -> bool
        def asts? = @asts

        # Whether a file uses rubygems' API. If so, it loads when the
        # program boots, as ruby loads it for every program.
        #: () -> bool
        def gems? = @gems

        # Whether rubygems loads as the program boots: not under
        # `--disable-gems`, where `Gem` is a name like any other.
        #: () -> bool
        def boots_gems? = @switches.gems

        # Whether `Gem` is an autoload of rubygems: a program that compiles
        # at run time, and does not load rubygems as it boots, can reach a
        # file that uses Gem, which ruby has for every file.
        #: () -> bool
        def lazy_gems? = @evals && !@gems && boots_gems?

        # Whether each String literal keeps where it was made
        # (--debug=frozen-string-literal).
        #: () -> bool
        def debug_frozen_strings? = @switches.debug_frozen_string_literal
        GEM_NAMES = %i[Gem Bundler].freeze

        # rubygems evals when it loads, so a program that includes it also
        # links in the compiler.
        #: (Symbol name) -> void
        def gems!(name)
          return unless GEM_NAMES.include?(name) && boots_gems?

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

        #: () -> bool
        def normalizes? = @normalizes
        #: () -> bool
        def pretty_prints? = @pretty_prints
        #: () -> bool
        def irbs? = @irbs

        #: () -> bool
        def configures? = @configures
        #: () -> bool
        def configures! = @configures = true

        # Whether a file uses the toplevel `RbConfig`, bare or as
        # `::RbConfig`.
        #: (Prism::node tree) -> bool
        def names_rbconfig?(tree)
          !tree.breadth_first_search do |n|
            case n
            when Prism::ConstantReadNode then n.name == :RbConfig
            when Prism::ConstantPathNode then n.parent.nil? && n.name == :RbConfig
            end #: bool
          end.nil?
        end

        #: (Symbol name, Array[untyped] args) -> void
        def normalizes!(name, args)
          named = args.first.value if args.first.is_a?(Literal) && args.first.value.is_a?(Symbol)
          @normalizes = true if NORMALIZES.include?(name) || ENCODES.include?(name) ||
                                ((SENDS + FETCHES).include?(name) && (NORMALIZES + ENCODES).include?(named))
          # A program that calls pp includes pp.rb, which the first call loads.
          # A send whose name is computed (or a String) may reach pp too.
          dynamic = (SENDS + FETCHES).include?(name) && args.first && !(args.first.is_a?(Literal) && args.first.value.is_a?(Symbol))
          @pretty_prints = true if name == :pp || ((SENDS + FETCHES).include?(name) && named == :pp) || dynamic
          # A program that calls irb includes irb, which `binding.irb` loads.
          @irbs = true if name == :irb || ((SENDS + FETCHES).include?(name) && named == :irb)
        end

        # The byte a file's `__END__` data starts at, or nil when it has
        # none.
        #: (String file) -> Integer?
        def data_at(file) = @data[file]

        # The script encoding that `__ENCODING__` answers. Prism's
        # result gives the source String's own encoding when the text is
        # not ASCII, so the magic comment is read again here, where ruby
        # reads it: line 1, or line 2 after a shebang, with spaces before the
        # `:` or `=` as well. A UTF-8 byte order mark reads as UTF-8. With
        # no comment, an eval's code has the encoding of its String, as
        # rb_parser does.
        #: (Prism::ParseResult result, String source, bool eval) -> Encoding
        def source_encoding(result, source, eval)
          bytes = source.b
          return ::Encoding::UTF_8 if bytes.start_with?("\xEF\xBB\xBF".b)

          lines = bytes.lines.first(2)
          lines = lines.first(1) unless lines.first&.start_with?("#!")
          name = lines.filter_map { |line| line[/\A\s*#.*?coding\s*[:=][ \t]*([\w.-]+)/i, 1] }.first
          return eval && source.encoding.ascii_compatible? ? source.encoding : result.encoding unless name

          ::Encoding.find(name) #: Encoding
        rescue ArgumentError
          result.encoding
        end

        # @rbs file: String
        # @rbs source: String
        # @rbs line: Integer
        # @rbs scopes: Array[Array[Symbol]]?
        # @rbs method: Array[[Symbol, Symbol?]]?
        # @rbs return: Unit
        def unit(file, source = File.read(file), line = 1, scopes = nil, method: nil)
          options = @switches.parse_options(main?(file) && scopes.nil?)
          # An eval's code starts in the encoding of its String, as
          # rb_parser reads it, until a magic comment on its first line.
          options = options.merge(encoding: source.encoding) if scopes && source.encoding.ascii_compatible?
          result = if scopes
                     Zr.parse(source, filepath: file, line: line, scopes: Loader.prism_scopes(scopes), **options)
                   else
                     Zr.parse(source, filepath: file, line: line, **options)
                   end
          raise SyntaxReport.error(result, file) unless result.errors.empty?
          if (marker = result.data_loc) && !(@switches.inline && main?(file))
            @data[file] = source.byteindex("\n", marker.start_offset)&.succ || source.bytesize
          end
          stray = scopes && (method.nil? ? invalid_yields(source, file, line) : class_yields(result.value, file)) #: SyntaxError?
          raise stray if stray

          load_path_roots(result.value, file).each do |front, paths|
            front ? @roots.unshift(*paths) : @roots.concat(paths)
          end
          configures! if !configures? && names_rbconfig?(result.value)
          @traces ||= !Library::Roots.runtime_file?(file) && TRACE_NAMES.match?(source.b) && names_tracing?(result.value)
          @covers ||= !Library::Roots.runtime_file?(file) && COVERAGE_NAMES.match?(source.b) && names_coverage?(result.value)
          @coverable[file] = [source.lines.size, []] if @trace && !Library::Roots.runtime_file?(file)
          build = Build.new(file, self, source_encoding(result, source, !scopes.nil?), shadowed: shadowed(result.value), root: result.value,
                                                                         eval: !scopes.nil?)
          build.within_method(method, scopes) if scopes && method
          # An activation entry belongs to the program, not the file, so
          # the unit cache cannot keep a file that takes one.
          rows = @activations
          body = build.seq(result.value.statements, hoist: true)
          @eval_using_after = build.top_using if scopes
          unless @eval || @hiding || file.start_with?("<") || Library::Roots.runtime_file?(file)
            spots = Spots.for(result, source, { filepath: file, line: line })
          end
          Unit.new(file, result.value.locals + build.temps, body, warnings(result, file) + build.warnings, Library::Roots.internal_library?(file), spots, @hiding,
                   source, @activations != rows, build.node_ids)
        end

        # An eval's outer scopes for prism. A method's anonymous `*`, `**`
        # and `&` (and `...`, which declares all three) are what the scope
        # forwards, not locals, so `eval "foo(*)"` parses as in ruby.
        #: (Array[Array[Symbol]] scopes) -> Array[Array[Symbol] | Prism::Scope]
        def self.prism_scopes(scopes)
          forwarded = Build::ANONYMOUS.values
          scopes.map do |locals|
            forwards = locals & forwarded
            next locals if forwards.empty?

            forwards += [:"..."] if forwards.size == forwarded.size
            Prism.scope(locals: locals - forwarded, forwarding: forwards)
          end
        end

        # The SyntaxError for a `yield` in an eval string, outside any
        # `def` in the string, when the eval is outside a method: there is
        # no block to yield to. prism reports it only if it does not know
        # about the outer scopes, so parse again without them. Ruby
        # reports each one, one line each.
        #: (String source, String file, Integer line) -> SyntaxError?
        def invalid_yields(source, file, line)
          yields = Zr.parse(source, filepath: file, line: line).errors.select { |e| e.type == :invalid_yield }
          return nil if yields.empty?

          message = yields.map { |e| "#{file}:#{e.location.start_line}: #{e.message}" }.join("\n")
          Hir.syntax_error(message, file).tap { |exc| exc.set_backtrace([file]) }
        end

        # The SyntaxError for a `yield` in a class, module or singleton
        # class body of an eval string, outside any `def` in it: ruby's
        # compiler refuses it even when the eval runs in a method, which
        # prism allows.
        #: (Prism::node root, String file) -> SyntaxError?
        def class_yields(root, file)
          found = class_yield_nodes(root, false, [])
          return nil if found.empty?

          message = found.map { |node| "#{file}:#{node.location.start_line}: Invalid yield" }.join("\n")
          Hir.syntax_error(message, file).tap { |exc| exc.set_backtrace([file]) }
        end

        # The `yield`s under `node` that a class, module or singleton class
        # body holds (`inside`), outside any `def`.
        #: (Prism::node node, bool inside, Array[Prism::YieldNode] found) -> Array[Prism::YieldNode]
        def class_yield_nodes(node, inside, found)
          case node
          when Prism::DefNode then return found
          when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode then inside = true
          when Prism::YieldNode then found << node if inside
          end
          node.compact_child_nodes.each { |child| class_yield_nodes(child, inside, found) }
          found
        end

        # The definees for which this file defines its own `require`,
        # `require_relative` or `load`. A call in one of them dispatches to
        # that method, so it must not compile the file in.
        # @rbs node: Prism::node?
        # @rbs path: Array[String?]
        # @rbs found: Hash[[String, bool, Symbol], bool]
        # @rbs singleton: bool
        # @rbs return: Hash[[String, bool, Symbol], bool]
        def shadowed(node, path = [Object.name], found = {}, singleton: false)
          case node
          when Prism::ClassNode, Prism::ModuleNode
            shadowed(node.body, path + [node.constant_path.slice], found) if node.body
          when Prism::SingletonClassNode
            shadowed(node.body, path, found, singleton: true) if node.body
          when Prism::DefNode
            found[[path.join("::"), !node.receiver.nil? || singleton, node.name]] = true if REQUIRES.include?(node.name)
          else
            node&.child_nodes&.each { |child| shadowed(child, path, found, singleton: singleton) }
          end
          found
        end

        # Ruby's parse-time warnings for the file (`key :k is duplicated
        # and overwritten on line 24` and similar), as ruby prints them.
        # prism knows the rules and the line of each. A warning of the `-w`
        # level starts with VERBOSE_WARNING: the run prints it only under a
        # true $VERBOSE.
        #: (Prism::ParseResult result, String file) -> Array[String]
        def warnings(result, file)
          result.warnings.map do |w|
            text = "#{Paths.shown(file)}:#{w.location.start_line}: warning: #{w.message}"
            w.level == :default ? text : VERBOSE_WARNING + text
          end
        end

        # The mark at the head of a warning that only a true $VERBOSE prints.
        VERBOSE_WARNING = "\x01"

        # The index of `path`'s unit, built at first use. The index entry
        # is set before the file is read, so two files that require each
        # other stop where ruby stops: the second require returns false
        # and the first one finishes.
        #: (String path) -> entry
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
          # The slot is held while the file builds, and the units that it
          # requires go after it.
          held = nil #: untyped
          @units << held
          @units[i] = if Library::Roots.description?(path)
                        # `resolve` finds this file only with a description.
                        text = @description&.call or raise ArgumentError, "#{path} has no description text"
                        unit(path, text)
                      elsif path == Library::Roots::SWITCHES
                        unit(path, @switches.prelude || raise(ArgumentError, "the build has no switches' prelude"))
                      elsif extension?(path)
                        source = Ext.bundles.fetch(path)
                        Unit.new(path, [], ExtInit.new(source.init, path, 1, source.library), [], false)
                      else
                        parsed_unit(path)
                      end
          i
        end

        # A required file, or, when it does not parse, a unit that raises
        # its SyntaxError where the require runs, as ruby's require does.
        #: (String path) -> Unit
        def parsed_unit(path)
          unit(path)
        rescue SyntaxError => e
          raise if main?(path)

          unit(path, "raise ::SyntaxError.new(#{e.message.inspect}).tap { |error| error.instance_variable_set(:@path, #{path.inspect}) }\n")
        end

        # A unit that stops with a message when it runs. An autoload of a
        # feature that this runtime has no file for becomes this: the
        # autoload entry exists, and a read of the constant stops.
        #: (String what, Integer line) -> Integer
        def stop_unit(what, line)
          i = @units.size
          @units << Unit.new(what, [], Stop.new(what, line), [], false)
          i
        end

        # Whether a missing literal require stops the build (`gate`).
        #: () -> (bool | Symbol)
        def gated? = @gate

        # The program's own files: the main file, and each file that one of
        # them reaches by `require_relative` or by a path. A file that a
        # require finds in a root is a library's.
        #: (String path) -> bool
        def own!(path) = @own[File.expand_path(path)] = true
        #: (String path) -> bool
        def own?(path) = @own.key?(File.expand_path(path))

        # Whether `path` is a file of one of the build's gems (`--gem` or
        # the Gemfile.lock), not of zr's standard library.
        #: (String path) -> bool
        def gem_file?(path) = @gem_set&.gems&.any? { |gem| gem.holds?(path) } || false

        # The program's main file, whose name came from the command line.
        #: (String path) -> void
        def main!(path)
          own!(path)
          @main = File.expand_path(path)
        end

        #: (String path) -> bool
        def main?(path) = @main == File.expand_path(path)

        # Why a build cannot use the file at `path`: it is in a gem of the
        # GemSet that zr cannot compile (a C extension). Nil otherwise.
        #: (String? path, ?String? feature) -> String?
        def refused_gem(path, feature = nil) = @gem_set&.refused(path, feature)

        # Each gem of the set that the program reaches whose C part zr does
        # not port. The build says so once for each (`Build.program`).
        #: (GemSet::Entry gem) -> void
        def native_gem!(gem) = (@native_gems << gem unless @native_gems.include?(gem))

        attr_reader :native_gems #: Array[GemSet::Entry]

        # A file's real path, as ruby's rb_current_realfilepath, or the path
        # as given when no file is there. A require_relative starts from it,
        # so a file loaded through a symlink requires relative to the file
        # that the link names.
        #: (String path) -> String
        def self.real_path(path) = File.exist?(path) ? File.realpath(path) : path

        # The file for `feature`, required from `from`, or nil.
        #: (Symbol kind, String feature, String from) -> String?
        def resolve(kind, feature, from)
          if kind == :require_relative
            candidate(File.expand_path(feature, File.dirname(Loader.real_path(from))))
          elsif feature.start_with?("/", "./", "../", "~")
            # A path relative to the working directory, as ruby reads it:
            # never relative to the requiring file.
            candidate(File.expand_path(feature))
          elsif feature == "zr_description" && @description
            # The kernel's description, which the runtime gives
            # (`Runtime#carried_text`); no root holds it.
            Library::Roots::DESCRIPTION
          else
            # A $LOAD_PATH directory is searched by its real path, as ruby
            # expands the load path, so a file found through a symlinked
            # directory has the path of the file the link names.
            @roots.each do |root|
              real = real_root(root)
              found = candidate(File.join(real, feature)) || native(root, feature) || extension(real, feature)
              return found if found
            end
            # rb_f_load: a name that no root has is a path from the working
            # directory, as it is written.
            here = File.expand_path(feature)
            kind == :load && File.file?(here) ? here : nil
          end
        end

        # The real path of directory `root`, or `root` when it is not there.
        #: (String root) -> String
        def real_root(root)
          roots = @real_roots ||= {} #: Hash[String, String]
          roots[root] ||= File.directory?(root) ? File.realpath(root) : root
        end

        # A native extension's name: `strscan.so`, `date.bundle`.
        NATIVE = /\.(?:so|bundle|dylib|o)\z/

        # The file in place of native extension `feature` under `root`:
        # the extension's own Ruby (`strscan.rb`), if the root contains
        # this runtime's native parts.
        #: (String root, String feature) -> String?
        def native(root, feature)
          native_root?(root) && feature.match?(NATIVE) ? candidate(File.join(root, feature.sub(NATIVE, ""))) : nil
        end

        # The bundle of a C extension that the build links in
        # (`Ext.bundles`), for `feature` under the directory
        # `dir`: `hello` and `hello.so` find `dir/hello.bundle`, as ruby's
        # require finds a darwin extension.
        #: (String dir, String feature) -> String?
        def extension(dir, feature)
          path = File.join(dir, "#{feature.sub(NATIVE, "")}.bundle")
          extension?(path) ? path : nil
        end

        #: (String path) -> bool
        def extension?(path) = Ext.bundles.key?(path)

        # Whether the build links a C extension under one of `roots`.
        #: (Array[String] roots) -> bool
        def extension_in?(roots) = Ext.bundles.each_key.any? { |path| roots.any? { |root| path.start_with?("#{root}/") } }

        # Library::Layout::EXT, or an OS layer's directory under it.
        #: (String root) -> bool
        def native_root?(root) = root == Library::Layout::EXT || File.dirname(root) == File.join(Library::Layout::EXT, "os")

        #: (String path) -> String?
        def candidate(path)
          return path if path.end_with?(".rb") && File.file?(path)

          File.file?("#{path}.rb") ? "#{path}.rb" : nil
        end

        # The directories that a file adds to $LOAD_PATH with a literal, in
        # order: `[true, paths]` for an `unshift`, which puts them before
        # all roots, and `[false, paths]` for `push` and `<<`.
        #: (Prism::node node, String file) -> Array[[bool, Array[String]]]
        def load_path_roots(node, file)
          roots = [] #: Array[[bool, Array[String]]]
          # @type var walk: ^(Prism::node) -> void
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

        # The absolute path of a literal: a String (frozen or not), `File.expand_path(str,
        # __dir__)`, `File.expand_path(str, __FILE__)` or `File.join(__dir__,
        # str...)`, where `File.dirname(__FILE__)` can stand for `__dir__`.
        # nil for all others.
        #: (Prism::node node, String file) -> String?
        def literal_path(node, file)
          dir = File.dirname(file)
          case node
          when Prism::StringNode then File.expand_path(node.unescaped)
          when Prism::InterpolatedStringNode
            parts = node.parts #: untyped
            return nil unless parts.size == 2 && parts[0].is_a?(Prism::EmbeddedStatementsNode) && parts[0].statements&.body&.size == 1 &&
                              dir_call?(parts[0].statements.body[0]) && parts[1].is_a?(Prism::StringNode)

            File.expand_path(dir + parts[1].unescaped)
          when Prism::CallNode
            # `"lib".freeze`, as the prelude of `-I` writes each directory.
            return literal_path(node.receiver, file) if node.name == :freeze && node.receiver && node.arguments.nil? && node.block.nil?
            return nil unless node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :File && node.arguments

            args = node.arguments.arguments #: untyped
            if node.name == :expand_path && args.size == 2 && args[0].is_a?(Prism::StringNode) && dir_call?(args[1])
              File.expand_path(args[0].unescaped, dir)
            elsif node.name == :expand_path && args.size == 2 && args[0].is_a?(Prism::StringNode) && args[1].is_a?(Prism::SourceFileNode)
              File.expand_path(args[0].unescaped, file)
            elsif node.name == :join && dir_call?(args[0]) && args[1..].all?(Prism::StringNode)
              File.join(dir, *args[1..].map(&:unescaped))
            end
          end
        end

        # `__dir__`, or `File.dirname(__FILE__)`: the directory of the file.
        #: (Prism::node? node) -> bool
        def dir_call?(node)
          return false unless node.is_a?(Prism::CallNode)
          return node.receiver.nil? && node.arguments.nil? if node.name == :__dir__

          args = node.arguments&.arguments || [] #: Array[Prism::node]
          node.name == :dirname && node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :File &&
            args.size == 1 && args[0].is_a?(Prism::SourceFileNode)
        end
      end
    end
  end
end
