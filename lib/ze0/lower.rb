# frozen_string_literal: true

module Ze0
  # A form the subset does not lower. The program is refused at the node,
  # never compiled to something that answers differently from ruby.
  class Unsupported < StandardError
    # The file the node was written in, which a spliced `require_relative`
    # makes different from the one the compile was asked for. Stamped as
    # the refusal passes back out of the file being read.
    attr_accessor :file

    def initialize(node, what = nil)
      kind = node.class.name.sub("Prism::", "").sub(/Node\z/, "")
      super("line #{node.location.start_line}: #{what || kind} is not in ze0's subset")
    end
  end

  # A value: where it sits, and who owns it.
  #
  # `at` is a stack slot (`ssN`) or a value holding an address (`vN`, a
  # caller's slot). `owned` says this code holds a reference it must move
  # or pool; a local variable's value is only ever borrowed. `immediate`
  # says the tag can never be a heap tag, so no ownership code is needed.
  Operand = Struct.new(:at, :owned, :immediate)

  # Ruby -> CLIF, one function at a time.
  #
  # The shape is the Rust emitter's outlined form: frames, lines, the
  # release pool and every dispatch are calls into the runtime; Integer
  # arithmetic and comparison take an inline fast path when both tags say
  # Int, and every other send is the runtime's cached dynamic send.
  # An `END { }` body, wearing the shape `lower_block` reads: no
  # parameters, no block-local names, and its statements as the body.
  EndBlock = Struct.new(:statements, :location) do
    def parameters = nil
    def body = statements
    def locals = []
    def compact_child_nodes = [statements].compact
  end

  class Lower
    include Patterns

    INT_ARITH = {
      :+ => ["sadd_overflow", "zeo_rt_int_add_slow"],
      :- => ["ssub_overflow", "zeo_rt_int_sub_slow"],
      :* => ["smul_overflow", "zeo_rt_int_mul_slow"],
    }.freeze
    INT_COMPARE = { :< => "slt", :> => "sgt", :<= => "sle", :>= => "sge", :== => "eq" }.freeze

    # The two halves of a name that an operator assignment both reads and
    # writes.
    Target = Struct.new(:read, :write)

    def initialize(program, roots = [])
      @program = program
      # Methods by owner and then by `[name, singleton]`, so a class's
      # `bar` and the top level's do not collide, and neither do `def x`
      # and `def self.x`. `@classes` is in declaration order.
      @defs = { Names::OBJECT => {} }
      # Every `def` node the declaration pass walked, so a redefinition --
      # whose row the later `def` replaced -- is still known to be one the
      # pass reached, and only a `def` written somewhere the pass does not
      # go is refused.
      @declared_defs = {}
      @declared_macros = {}
      @classes = {}
      @scopes = []
      @blocks = 0
      @file = program.file
      # Every name any class body marked `private_constant`. A read of a
      # name no body marks can never need the guard, whatever its scope.
      @private_constants = {}
      # The features already required, so a second `require` of one
      # answers false the way ruby's does.
      @required = {}
      # The top-level local names of each file the splice read. Each file
      # is its own scope in ruby, so each gets its own table of slots.
      @unit_locals = {}
      # Every `autoload` read so far that no statement has reached, and
      # the node each was written at, so a flushed unit names its line.
      @autoloads = {}
      @autoload_nodes = {}
      # The lexical scopes a constant search walks where the declaration
      # pass has reached, innermost first. `Object` is always last and is
      # left out.
      @cref = []
      @roots = roots
      # The files a `require` the splice cannot consume names, each
      # compiled as its own function, and the spellings that reach it.
      @deferred = {}
      # The require CALLS the splice did not consume, which stay where
      # they are and ask the run time.
      @deferred_call = {}
      @units = 0
    end

    def lower(root)
      @root = root
      units = []
      # The main file is NOT seeded into the loading table: ruby has no
      # entry for it either, so a `require_relative` that names it back
      # loads it a second time.
      @unit_locals[@program.file] = root.locals
      seen = {}
      splice(body_statements(root.statements), @program.file, seen, units)
      deferred = read_deferred(seen)
      units.each { |file, statements| with_file(file) { declare(statements, Names::OBJECT) } }
      deferred.each_value do |unit|
        unit[:runs].each { |file, statements| with_file(file) { declare(statements, Names::OBJECT) } }
      end
      @defs.each_value do |by_key|
        by_key.each_value { |d| with_file(d[:file]) { lower_def(d) } }
      end
      @classes.each_value do |c|
        c[:bodies].each { |written| with_file(written[:file]) { lower_class_body(c, written) } }
      end
      lower_toplevel(units)
      deferred.each_value { |unit| lower_top_scope(unit[:symbol], unit[:runs]) }
    end

    private

    # ---- the files ----
    #
    # `require_relative` resolves HERE, not at run time: the target is
    # parsed and its statements are spliced in at the call's position,
    # once per file. That is the only `require` shape ze0 has -- a real
    # one searching a load path, and a lazily linked unit, are refused.
    #
    # `units` come out in load order, each a run of statements from one
    # file, so a `def` records the file its backtrace has to name.

    # The file whose statements are being read. A `def` and a class body
    # keep theirs, because a frame names the file it was WRITTEN in.
    def with_file(file)
      previous = @file
      @file = file
      value = yield
      @file = previous
      value
    rescue Unsupported => e
      e.file = file if e.file.nil?
      raise
    end

    def splice(statements, file, seen, units)
      run = []
      mine = []
      close = -> do
        units << [file, run] unless run.empty?
        run = []
      end
      splice_in = ->(node, path) do
        close.call
        read_unit(node, path, seen, units)
      end
      statements.each do |s|
        mine.concat(register_autoloads(s))
        # A pending `autoload` whose constant this statement reaches goes
        # in BEFORE it, which is where CRuby's own first access would have
        # loaded the file. A unit is a run of TOP-LEVEL statements, so the
        # run so far closes first.
        reached_autoloads(s).each { |path| splice_in.call(s, path) }
        target = required_file(s, file)
        if target.nil?
          note_deferred(s, file)
          run << s
          next
        end

        splice_in.call(s, target)
      end
      close.call
      # An `autoload` no statement reached still names a file this program
      # has to carry, and the end of the file that wrote it is where it
      # costs the least: everything the file itself declares is in place,
      # and nothing that requires the file has run yet.
      #
      # This is ze0's standing divergence, and zeo's own
      # (`parse/loader/mod.rs`): the file runs even though the constant is
      # never referenced, because there are no lazy units.
      mine.each do |name|
        path = @autoloads.delete(name)
        read_unit(@autoload_nodes.fetch(name), path, seen, units) if path
      end
    end

    # Every `autoload` under `node`, filed by the constant it provides,
    # and the names it added. A splice removes the entry, so each file
    # goes in once.
    def register_autoloads(node, added = [])
      if autoload_call?(node) && (path = autoload_target(node))
        name = autoload_name(node)
        added << name unless @autoloads.key?(name)
        @autoloads[name] ||= path
      end
      node.compact_child_nodes.each { |c| register_autoloads(c, added) }
      added
    end

    # The pending autoload files `node` reaches while it RUNS, in the
    # order the constants are written.
    def reached_autoloads(node)
      load_time_constants(node).uniq.filter_map { |name| @autoloads.delete(name) }
    end

    # The constants `node` can reach WHILE IT RUNS: a superclass clause,
    # an `include`, a class body's own statements. A `def` body is not
    # one -- it runs when it is called, which is after the program has
    # loaded, so a constant only a method names never loads a file here.
    def load_time_constants(node, found = [])
      return found if node.is_a?(Prism::DefNode)

      found << node.name.to_s if CONSTANT_READS.any? { |k| node.is_a?(k) }
      node.compact_child_nodes.each { |c| load_time_constants(c, found) }
      found
    end

    CONSTANT_READS = [Prism::ConstantReadNode, Prism::ConstantPathNode].freeze

    # `path`'s statements as units, once per program.
    def read_unit(node, path, seen, units)
      # The entry goes in BEFORE the file is read, matching CRuby's
      # loading table: a cycle splices nothing the second time.
      return if seen.key?(path)

      seen[path] = true
      # Read the file where the `require` is written, so a refusal about
      # the file names the line that asked for it.
      statements = spliced_statements(node, path)
      with_file(path) { splice(statements, path, seen, units) }
    end

    # The verbs that bring another file's statements into the program.
    LOAD_CALLS = %i[require require_relative load].freeze

    # `load` runs the file EVERY time and consults no loaded-feature
    # table, so a unit -- which runs once -- can never answer one. It
    # reads the file at run time, which is what the compiler this asks
    # for is there to do.
    RELOADS = %i[load].freeze

    # A `require` the splice cannot consume: one an `if` guards, one
    # inside a method or a block, one whose name is computed. The call
    # stays where it is, and the file it names becomes a UNIT the
    # run-time require runs -- which is ruby's own order, since whether
    # the call runs at all is a run-time fact.
    def note_deferred(node, file)
      requires_under(node).each do |call|
        # The splice has already judged the STATEMENT itself. A literal
        # one it left behind names a feature the runtime holds, and
        # `lower_require` opens that gate where it stands.
        next if call.equal?(node) && literal_feature?(call)

        @deferred_call[call.object_id] = true
        next @program.eval_install! if RELOADS.include?(call.name)

        path = literal_target(call, file)
        # A name only the run time builds names no file here: the call
        # asks the run time, which answers from the units this program
        # carries and reads the file itself otherwise. A plain `require`
        # may also name any gated builtin, so every one is registered.
        if path.nil?
          @program.eval_install!
          @program.require_any_feature! if call.name == :require
          next
        end

        note_unit(path, unit_spellings(call, path))
      end
    end

    def note_unit(path, spellings)
      entry = (@deferred[path] ||= { spellings: [] })
      entry[:spellings] |= spellings
    end

    # Every `require`, `require_relative` and `load` written under
    # `node`. The splice takes only a top-level statement, so whatever
    # this finds is one the splice left behind.
    def requires_under(node, found = [])
      found << node if node.is_a?(Prism::CallNode) && node.receiver.nil? && LOAD_CALLS.include?(node.name)
      node.compact_child_nodes.each { |child| requires_under(child, found) }
      found
    end

    # Whether the call names its file with a plain string literal.
    def literal_feature?(node)
      args = node.arguments&.arguments || []
      args.size == 1 && args[0].is_a?(Prism::StringNode) && node.block.nil?
    end

    # The file one call names, or nil where only the run time can say.
    def literal_target(node, file)
      return nil unless literal_feature?(node)

      feature = node.arguments.arguments[0].unescaped
      return with_rb(File.expand_path(feature, File.dirname(file))) unless node.name == :require

      @roots.filter_map { |root| with_rb(File.expand_path(feature, root)) }.first
    end

    # The spellings a run-time require may use for this file. The runtime
    # strips a `.rb` suffix, so neither spelling carries one: the
    # absolute path is what `require_relative` expands to, and the
    # feature as written is what a load-path `require` asks for.
    def unit_spellings(node, path)
      spellings = [path.delete_suffix(".rb")]
      spellings << canonical_feature(node.arguments.arguments[0].unescaped) if node.name == :require
      spellings
    end

    # Each deferred file as its own run of statements, read once. A file
    # the splice already took is refused rather than compiled twice: one
    # file, one mechanism.
    def read_deferred(seen)
      done = {}
      until (path = (@deferred.keys - done.keys).first).nil?
        entry = @deferred.fetch(path)
        raise Unsupported.new(@root, "a `require` of a file the splice already took") if seen.key?(path)

        seen[path] = true
        runs = []
        statements = spliced_statements(@root, path)
        with_file(path) { splice(statements, path, seen, runs) }
        symbol = "zeo_unit_#{@units}"
        @units += 1
        entry[:spellings].each { |spelling| @program.add_unit(spelling, symbol) }
        done[path] = entry.merge(symbol: symbol, runs: runs)
      end
      done
    end

    # The absolute path a `require_relative` names, or nil for any other
    # statement. Resolved against the requiring FILE's directory, never
    # the working directory, and `.rb` is appended AFTER the path is made
    # absolute -- CRuby's order.
    def required_file(node, file)
      return nil unless node.is_a?(Prism::CallNode) && node.receiver.nil?
      return nil unless node.name == :require_relative || node.name == :require

      # A name only the run time can build names no file here: the call
      # stays where it is and resolves against the units this program
      # carries.
      return nil unless literal_feature?(node)

      feature = node.arguments.arguments[0].unescaped
      if node.name == :require_relative
        path = with_rb(File.expand_path(feature, File.dirname(file)))
        raise Unsupported.new(node, "`require_relative \"#{feature}\"`, which names no file") if path.nil?

        return path
      end

      # A plain `require` searches the roots `-I` named, in order. One no
      # root carries names a feature the runtime already holds, and the
      # call stays where it is: `lower_require` opens the gate there.
      @roots.filter_map { |root| with_rb(File.expand_path(feature, root)) }.first
    end

    def autoload_call?(node)
      node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name == :autoload
    end

    # The file one `autoload` names, searched the way `require` searches
    # -- which is what ruby's `autoload` does with its second argument.
    # nil when no root carries it: the feature is then the runtime's own,
    # and the declaration opens its gate where it stands.
    def autoload_target(node)
      feature = autoload_feature(node)
      @roots.filter_map { |root| with_rb(File.expand_path(feature, root)) }.first
    end

    # The constant one `autoload` provides. The node is kept beside it so
    # a flushed unit still names the line that asked for the file.
    def autoload_name(node)
      name = node.arguments.arguments[0]
      unless name.is_a?(Prism::SymbolNode)
        raise Unsupported.new(node, "an `autoload` of that shape")
      end

      @autoload_nodes[name.unescaped] = node
      name.unescaped
    end

    def autoload_feature(node)
      args = node.arguments&.arguments || []
      unless args.size == 2 && args[1].is_a?(Prism::StringNode) && node.block.nil?
        raise Unsupported.new(node, "an `autoload` of that shape")
      end

      args[1].unescaped
    end

    # A required path, with `.rb` appended AFTER it is absolute -- CRuby's
    # order -- or nil when neither spelling names a file.
    def with_rb(path)
      return path if File.file?(path)

      "#{path}.rb" if File.file?("#{path}.rb")
    end

    def spliced_statements(node, path)
      result = Prism.parse_file(path)
      unless result.errors.empty?
        error = result.errors.first
        raise Unsupported.new(node, "a required file with a syntax error: #{error.message}")
      end
      @unit_locals[path] = result.value.locals
      body_statements(result.value.statements)
    end

    # ---- the scope being lowered ----
    #
    # A block body will lower inside the method that wrote it, so these
    # read the top of the stack rather than one set of instance variables.
    # None may be named for a `Kernel` method: a private method on `Lower`
    # overrides one for every instance of it.

    def scope = @scopes.last
    def f = @scopes.last.f
    def kind = @scopes.last.kind
    def locals = @scopes.last.locals
    def self_operand = @scopes.last.self_operand
    def out = @scopes.last.out
    def rodata = @scopes.last.rodata
    def syms = @scopes.last.syms
    def owner = @scopes.last.owner
    def cref = @scopes.last.cref
    def raise_block = @scopes.last.raise_block
    def done_block = @scopes.last.done_block

    # ---- declarations ----

    # One walk over a body, collecting what lowering has to know before it
    # starts. Today that is the `def`s, so a call written above a
    # definition still resolves to it; classes and captures join them.
    def declare(statements, owner, guarded: false)
      # A bare `private` or `protected` is a mode over the `def`s BELOW
      # it, so the walk carries it. Every top-level `def` is a private
      # method of Object, whatever the body says.
      visibility = "public"
      statements.each do |s|
        case s
        when Prism::DefNode then declare_def(s, owner, visibility) unless guarded
        when Prism::ClassNode then declare_class(s, owner, "class", guarded: guarded)
        when Prism::ModuleNode then declare_class(s, owner, "module", guarded: guarded)
        when Prism::CallNode then visibility = declare_macro(s, owner, visibility) unless guarded
        when Prism::IfNode, Prism::UnlessNode then declare_branches(s, owner, guarded)
        end
      end
    end

    # A guard this compile can decide has one branch that cannot run, and
    # the other's `def`s and classes are as much a part of the program as
    # any written beside it.
    #
    # One it cannot decide names a class the row still has to carry --
    # ids are the backend's and a class row cannot be minted while the
    # program runs -- but the row is CONCEALED, so the constant appears
    # only if the branch runs. A `def` there stays undeclared and the
    # body installs it where it stands, which is ruby's own order.
    def declare_branches(node, owner, guarded)
      return declare(branch_statements(live_branch(node)), owner, guarded: guarded) if decided?(node)

      [node.statements, node.is_a?(Prism::UnlessNode) ? node.else_clause : node.subsequent].each do |b|
        declare(branch_statements(b), owner, guarded: true)
      end
    end

    def decided?(node) = !Guards.static_cond(node.predicate).nil?

    # `attr_reader`, its two siblings, and the visibility verbs: the class
    # body macros ze0 answers at COMPILE time. Anything else keeps the
    # refusal `lower_call` gives it.
    ACCESSORS = { attr_reader: :reader, attr_writer: :writer, attr_accessor: :accessor }.freeze
    VISIBILITY = %w[public private protected].freeze
    # Not a visibility but a mode over the `def`s below it, like a bare
    # `private`: each one becomes a method of the module AND a private
    # instance method the includer gets.
    MODULE_FUNCTION = "module_function"

    def declare_macro(node, owner, visibility)
      return visibility if owner == Names::OBJECT || !node.receiver.nil?

      name = node.name.to_s
      args = node.arguments&.arguments || []
      if name == MODULE_FUNCTION
        @declared_macros[node.object_id] = true
        return MODULE_FUNCTION if args.empty?

        accessor_names(node, args).each { |n| declare_module_function(node, owner, n) }
        return visibility
      end
      if VISIBILITY.include?(name)
        # `private :x` is positional and retags one name where it is
        # written; only the bare verb is a mode. `private def x` declares
        # the method at that visibility and nothing runs at all.
        return name if args.empty?

        args.each { |a| declare_def(a, owner, name) if a.is_a?(Prism::DefNode) }
        return visibility
      end
      if name == "private_constant"
        @declared_macros[node.object_id] = true
        names = accessor_names(node, args)
        names.each { |n| @private_constants[n] = true }
        @classes.fetch(owner)[:private_constants].concat(names)
        return visibility
      end

      kind = ACCESSORS[node.name]
      return visibility unless kind

      @declared_macros[node.object_id] = true
      accessor_names(node, args).each { |n| declare_accessor(node, owner, n, kind, visibility) }
      visibility
    end

    # The names an `attr_*` or positional visibility call names. Each has
    # to be a plain Symbol: ze0 emits a method per name at compile time,
    # so a String or a computed one has nothing to emit.
    # These verbs take a name, and ruby lets it be written as a Symbol or
    # as a String.
    NAME_LITERALS = [Prism::SymbolNode, Prism::StringNode].freeze

    def accessor_names(node, args)
      args.map do |a|
        raise Unsupported.new(a, "a `#{node.name}` argument of that shape") unless NAME_LITERALS.any? { |k| a.is_a?(k) }

        a.unescaped
      end
    end

    # One generated accessor: a method row like any other `def`, with no
    # body function at all. The trampoline IS the method.
    def declare_accessor(node, owner, name, kind, visibility)
      readers = kind == :writer ? [] : [[name, :reader, []]]
      writers = kind == :reader ? [] : [["#{name}=", :writer, [["req", ""]]]]
      (readers + writers).each do |method, half, params|
        key = [method.to_sym, false]
        @defs[owner][key] = {
          accessor: half, ivar: name, owner: owner, singleton: false,
          name: method, line: node.location.start_line, file: @file,
        }
        @program.add_def(
          name: method,
          tramp: trampoline_of(owner, method, false),
          params: params,
          line: node.location.start_line,
          file: @file,
          owner: owner,
          singleton: false,
          visibility: visibility,
        )
      end
    end

    # A class or module, and everything its body declares. The backend
    # assigns the id; ze0 only ever names it, by the path it is written
    # at -- `Ze0::Lower`, which is what `Module#name` answers.
    def declare_class(node, owner, kind, guarded: false)
      name = declared_name(node)
      superclass = superclass_of(node, kind)
      entry = @classes[name] || declare_fresh_class(node, name, kind, superclass)
      entry[:guarded] ||= guarded
      if entry[:kind] != kind
        raise Unsupported.new(node, "a #{entry[:kind]} reopened as a #{kind}")
      end
      written = kind == "class" ? node.superclass : nil
      if written && entry[:superclass] != superclass
        raise Unsupported.new(written, "a class reopened with a different superclass")
      end

      body = body_statements(node.body)
      # The ivar list and the private-constant list are the ones the class
      # ROW holds, so a reopen adds to what the sidecar already carries.
      ivar_names(body, superclass).each { |n| entry[:ivars] << n unless entry[:ivars].include?(n) }
      cvar_names(body).each { |n| entry[:cvars] << n unless entry[:cvars].include?(n) }
      # A body's symbol is settled here, not when it is lowered: an
      # enclosing body calls it, and the two are lowered in either order.
      base = "zeo_cb_#{Names.owner_fragment(name)}"
      at = entry[:bodies].size
      # The body opens ONE cref frame, whatever the name's shape: a
      # qualified `class A::B::C` searches `C` and then whatever encloses
      # the statement, never `A::B`. Ruby's own rule, and the reason a
      # cref cannot be recovered by splitting a name.
      @cref.unshift(name)
      entry[:bodies] << {
        node: node, body: body, file: @file, cref: @cref.dup,
        symbol: at.zero? ? base : "#{base}_#{at}",
      }
      # A guarded body is the whole class: the reveal at its statement is
      # what makes the constant, and the rows the body writes are on a
      # class nothing else can name yet. A SECOND body would install its
      # methods whether the guard let it run or not.
      if entry[:guarded] && entry[:bodies].size > 1
        raise Unsupported.new(node, "a #{kind} reopened under a guard")
      end

      declare(body, name)
      @cref.shift
    end

    # The name a `class` or `module` statement declares: the path it
    # names, resolved outward, or the bare name qualified by the class the
    # statement is written in.
    def declared_name(node)
      path = node.constant_path
      return qualify(@cref.first || Names::OBJECT, node.name.to_s) if path.is_a?(Prism::ConstantReadNode)

      scope = path.parent && declared_class(@cref, path.parent)
      unless scope
        raise Unsupported.new(node, "a class named in a scope this program does not define")
      end

      "#{scope}::#{node.name}"
    end

    def declare_fresh_class(node, name, kind, superclass)
      entry = {
        name: name, kind: kind, superclass: superclass,
        ivars: [], cvars: [], private_constants: [], bodies: [],
      }
      @classes[name] = entry
      @defs[name] = {}
      @program.add_class(
        name: name,
        superclass: superclass,
        kind: kind,
        ivars: entry[:ivars],
        private_constants: entry[:private_constants],
        file: @file,
        line: node.location.start_line,
      )
      entry
    end

    # `Outer::Inner`, or the bare name at the top level.
    def qualify(owner, name)
      owner == Names::OBJECT ? name : "#{owner}::#{name}"
    end

    def superclass_of(node, kind)
      return Names::OBJECT if kind == "module" || node.superclass.nil?

      written = written_class_name(node.superclass)
      raise Unsupported.new(node.superclass, "a superclass of that shape") if written.nil?

      # A name this program does not declare goes through as written: the
      # backend resolves it against the builtin exceptions, whose ids it
      # owns, and refuses every other builtin -- `class Foo < String` is a
      # different native shape.
      declared_class(@cref, node.superclass) || written
    end

    # A superclass as it was WRITTEN, or nil for a shape that is not a
    # name at all: `Struct.new(:a)`, a variable, an anchored `::Foo`.
    def written_class_name(node)
      case node
      when Prism::ConstantReadNode then node.name.to_s
      when Prism::ConstantPathNode
        up = node.parent && written_class_name(node.parent)
        "#{up}::#{node.name}" if up
      end
    end

    # The row this program declares for that name, resolved outward from
    # the class the `class` statement is written in, or nil when no row
    # matches. A path's own scope has to be declared too: `A::B` names a
    # row only when this program wrote both halves.
    def declared_class(cref, node)
      case node
      when Prism::ConstantReadNode then resolve_class(cref, node.name.to_s)
      when Prism::ConstantPathNode
        up = node.parent && declared_class(cref, node.parent)
        "#{up}::#{node.name}" if up && @classes.key?("#{up}::#{node.name}")
      end
    end

    # A class name as written, resolved outward through `cref`: `Lower`
    # inside `Ze0` is `Ze0::Lower` before it is a top-level `Lower`.
    #
    # The cref is the LEXICAL nesting and not the name: a body written
    # `class A::B::C` sees `C` and whatever encloses the statement, never
    # `A::B`, so a name cannot be split back into the scopes it searches.
    def resolve_class(cref, name)
      (cref + [Names::OBJECT]).map { |scope| qualify(scope, name) }
                              .find { |candidate| @classes.key?(candidate) }
    end

    # The instance variables a class declares, in slot order: the ones a
    # superclass already declared, then the ones this body's methods name
    # in first-mention order. Parent first, so a slot index an inherited
    # method was compiled with still reads the same variable here.
    #
    # The names go in WITHOUT their `@`, which is the spelling
    # `ClassDesc.ivar_names` holds and `instance_variables` puts back.
    def ivar_names(body, superclass)
      found = {}
      @classes[superclass]&.fetch(:ivars)&.each { |n| found[n] = true }
      body.each { |n| ivars_under(n, found) }
      found.keys
    end

    # The class variables a body names, `@@` and all. A `def` in the body
    # counts: `@@x` in a method belongs to the class it is written in,
    # which is what makes this a per-CLASS list and not a per-method one.
    def cvar_names(body)
      found = {}
      body.each { |n| cvars_under(n, found) }
      found.keys
    end

    CVAR_NODES = [
      Prism::ClassVariableReadNode, Prism::ClassVariableWriteNode,
      Prism::ClassVariableOperatorWriteNode, Prism::ClassVariableOrWriteNode,
      Prism::ClassVariableAndWriteNode, Prism::ClassVariableTargetNode,
    ].freeze

    def cvars_under(node, found)
      return found if NESTED_BODIES.any? { |k| node.is_a?(k) }

      found[node.name.to_s.delete_prefix("@@")] = true if CVAR_NODES.any? { |k| node.is_a?(k) }
      node.compact_child_nodes.each { |c| cvars_under(c, found) }
      found
    end

    IVAR_NODES = [
      Prism::InstanceVariableReadNode, Prism::InstanceVariableWriteNode,
      Prism::InstanceVariableOperatorWriteNode, Prism::InstanceVariableOrWriteNode,
      Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableTargetNode,
    ].freeze

    # A nested class or module declares its own slots, so the walk stops
    # at one: its `@name` names a slot on ITS instances, and counting it
    # here would give the enclosing class a slot nothing ever reads.
    NESTED_BODIES = [Prism::ClassNode, Prism::ModuleNode].freeze

    def ivars_under(node, found)
      return found if NESTED_BODIES.any? { |k| node.is_a?(k) }

      found[node.name.to_s.delete_prefix("@")] = true if IVAR_NODES.any? { |k| node.is_a?(k) }
      # An `attr_reader :x` names no `@x` anywhere, and still declares its
      # slot: the generated accessor reads the slot by index.
      if node.is_a?(Prism::CallNode) && node.receiver.nil? && ACCESSORS.key?(node.name)
        accessor_names(node, node.arguments&.arguments || []).each { |n| found[n] = true }
      end
      node.compact_child_nodes.each { |c| ivars_under(c, found) }
      found
    end

    # A Prism parameter list as the shape the binder and the body agree
    # on. A destructuring parameter is refused: it binds names the slot
    # array has no room for.
    # A block's or lambda's parameters, in whichever of prism's three
    # shapes it was written. `_1`..`_N` and `it` are sugar for that many
    # required positionals -- the names ruby gives them and the arity it
    # answers -- so they need no lowering of their own.
    def block_params(node)
      case (list = node.parameters)
      when nil then parse_params(nil)
      # A `def` lowered as a closure: its list is a method's, with no
      # block-local names wrapped around it.
      when Prism::ParametersNode then parse_params(list)
      # A block-local (`|n; scratch|`) needs no row: prism already counts
      # it among the block's own names, which is what keeps it out of the
      # captures and gives it a fresh nil per invocation.
      when Prism::BlockParametersNode then parse_params(list.parameters)
      when Prism::NumberedParametersNode
        positionals((1..list.maximum).map { |i| "_#{i}".to_sym })
      when Prism::ItParametersNode then positionals([:it])
      else raise Unsupported.new(list, "a block parameter list of that shape")
      end
    end

    def positionals(names)
      Params.new(names, [], nil, [], [], nil, nil, false)
    end

    def parse_params(node)
      return positionals([]) if node.nil?

      return forwarding_params if node.keyword_rest.is_a?(Prism::ForwardingParameterNode)

      destructures = {}
      Params.new(
        node.requireds.map { |r| positional_name(r, destructures) },
        node.optionals.map { |o| Params::Optional.new(o.name, o.value) },
        rest_of(node.rest),
        node.posts.map { |r| positional_name(r, destructures) },
        node.keywords.map { |k| keyword_of(k) },
        kwrest_of(node.keyword_rest),
        block_param_name(node.block),
        node.keyword_rest.is_a?(Prism::NoKeywordsParameterNode),
        destructures,
      )
    end

    # The slot a `&` parameter binds. ruby names an ANONYMOUS one `&`,
    # the same name `...` gives it, so a forward written `&` reads it.
    def block_param_name(node)
      return nil if node.nil?

      node.name || :&
    end

    # `def f(...)` takes all three channels at once. ruby names them `*`,
    # `**` and `&`, which is what `Method#parameters` reports and what no
    # source can write as a local of its own.
    def forwarding_params
      Params.new([], [], Params::Star.new(:*), [], [], Params::Star.new(:**), :&, false)
    end

    # One positional parameter's slot name. A `(a, b)` destructure has no
    # name of its own in ruby, so it gets one no source can write and the
    # pattern is kept beside it.
    def positional_name(node, destructures)
      return node.name if node.is_a?(Prism::RequiredParameterNode)
      raise Unsupported.new(node, "a parameter of that shape") unless node.is_a?(Prism::MultiTargetNode)

      name = "(#{destructures.size})".to_sym
      destructures[name] = node
      name
    end

    # An `|a, |` trailing comma is prism's `ImplicitRestNode`: a rest that
    # binds nothing and is not in the signature, but which does turn the
    # auto-splat on. An anonymous `*` is a slot ruby names `*`, so a call
    # written `n(*)` can forward it.
    def rest_of(node)
      return nil if node.nil?
      return Params::Star.new(nil) if node.is_a?(Prism::ImplicitRestNode)
      raise Unsupported.new(node, "a rest parameter of that shape") unless node.is_a?(Prism::RestParameterNode)

      Params::Star.new(node.name || :*)
    end

    def kwrest_of(node)
      return nil if node.nil? || node.is_a?(Prism::NoKeywordsParameterNode)
      raise Unsupported.new(node, "a forwarding parameter") unless node.is_a?(Prism::KeywordRestParameterNode)

      Params::Star.new(node.name || :**)
    end

    def keyword_of(node)
      case node
      when Prism::RequiredKeywordParameterNode then Params::Keyword.new(node.name, nil, true)
      when Prism::OptionalKeywordParameterNode then Params::Keyword.new(node.name, node.value, false)
      else raise Unsupported.new(node, "a keyword parameter of that shape")
      end
    end

    def declare_def(node, owner, visibility = "public")
      singleton = node.receiver.is_a?(Prism::SelfNode)
      # `def obj.name` names an object no compile can know, so it has no
      # row: the statement installs it on that object's singleton where it
      # stands, which is where ruby installs it too.
      return if node.receiver && !singleton
      raise Unsupported.new(node, "a def on self at the top level") if singleton && owner == Names::OBJECT
      # A redefinition keeps the LAST body, as ruby does; the row and the
      # body symbol are the same either way.
      key = [node.name, singleton]
      @declared_defs[node.object_id] = true

      params = parse_params(node.parameters)
      definition = {
        params: params, node: node, block: params.takes_block?(uses_block?(node.body)),
        owner: owner, singleton: singleton, file: @file, cref: @cref.dup,
      }
      @defs[owner][key] = definition
      mixin = visibility == MODULE_FUNCTION
      add_def_row(definition, singleton: singleton, visibility: mixin ? "private" : visibility)
      module_function_row(definition) if mixin
    end

    # One `Def` row from a definition the declaration pass holds.
    def add_def_row(definition, singleton:, visibility:, tramp: nil)
      owner, node = definition[:owner], definition[:node]
      @program.add_def(
        name: node.name,
        tramp: tramp || trampoline_of(owner, node.name, singleton),
        params: definition[:params].rows,
        line: node.location.start_line,
        file: definition[:file],
        owner: owner == Names::OBJECT ? "" : owner,
        singleton: singleton,
        visibility: visibility,
      )
    end

    # The module's own half of a `module_function`. One body serves both
    # halves, so this row names the INSTANCE trampoline.
    def module_function_row(definition)
      owner, node = definition[:owner], definition[:node]
      add_def_row(
        definition, singleton: true, visibility: "public",
        tramp: trampoline_of(owner, node.name, false)
      )
    end

    # `module_function :name`, which names a `def` already written above
    # it. Ruby answers NameError for a name the module does not carry,
    # and ze0 refuses one it cannot see rather than guessing.
    def declare_module_function(node, owner, name)
      definition = @defs[owner][[name.to_sym, false]]
      raise Unsupported.new(node, "a `module_function` of a method this body does not define") unless definition

      add_def_row(definition, singleton: false, visibility: "private")
      module_function_row(definition)
    end

    # A `def` answers its own name. The declaration pass walks only the
    # statements of a program, class or module body, so one written
    # anywhere else -- inside a block, an `if`, a loop or another `def` --
    # has no row and is installed where it stands instead.
    def declared_def(node)
      return runtime_def(node) unless @declared_defs[node.object_id]

      literal_symbol(node.name)
    end

    # A `def` with no row. Which class it lands on is not known until the
    # statement runs -- inside `Module.new { }` it is the new module, in a
    # class body it is that class, at the top level it is `Object` -- so
    # the body becomes a lambda-shaped Proc and the runtime resolves the
    # definee the same way the interpreter does.
    def runtime_def(node)
      return define_singleton(lower_expr(node.receiver), node, "public") if node.receiver

      body, captures = lower_method_body(node)
      proc_value = proc_new(body, captures, node, true)
      result = f.slot
      # A `def` written at the TOP LEVEL is a private instance method of
      # Object however it is spelled, which is the caller's to say: where
      # it was WRITTEN is compile-time knowledge and the definee is not.
      private = owner == Names::OBJECT && kind != :class_body
      status_check(f.val(
        "call #{f.import("zeo_rt_define_in_default_definee")}(#{addr_of(cref_value)}, " \
        "#{borrow(self_operand)}, #{sym_id(node.name)}, #{proc_value}, " \
        "#{f.iconst("i8", private ? 1 : 0)}, #{f.iconst("i8", 0)}, #{addr_of(result)})",
      ))
      Operand.new(result, true, false)
    end

    # The class a `def` was WRITTEN in, as a value. The runtime compares it
    # with the live `self` to see which definee the statement is running
    # under, and falls back to this when none is open.
    def cref_value = class_value(owner)

    # One class, as a value. The backend assigns the id, so this reads it
    # out of `zeo_class_ids` rather than looking the constant up: the row
    # exists whatever a constant table says.
    def class_value(name)
      slot = f.slot
      at = addr_of(slot)
      store_nil(at)
      f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_CLASS)}, #{at}"
      id = name == Names::OBJECT ? f.iconst("i32", Capi::OBJECT_CLASS) : class_id(name)
      f.ins "store notrap aligned #{id}, #{at}+8"
      Operand.new(slot, false, true)
    end

    def body_symbol_of(owner, name, singleton)
      singleton ? Names.class_method_symbol(owner, name) : Names.method_symbol(owner, name)
    end

    def trampoline_of(owner, name, singleton)
      singleton ? Names.class_trampoline_symbol(owner, name) : Names.trampoline_symbol(owner, name)
    end

    def label_of(owner, name, singleton)
      singleton ? Names.class_method_label(owner, name) : Names.method_label(owner, name)
    end

    # ---- captures ----
    #
    # The crude rule the Rust emitter's 1,270-line analysis exists to
    # refine: a name is boxed when any block written in the scope mentions
    # it. That over-boxes -- a name a block only reads and nobody assigns
    # needs no cell -- and it is never wrong.

    # The locals of this scope that a block under `nodes` names.
    # `forwarded` are the parameters a bare `super` sends on. A block
    # that writes one names none of them, and the values still have to
    # outlive the frame, so such a block counts as mentioning them all.
    def captured_names(nodes, owned, forwarded = [])
      mentioned = {}
      nodes.each do |n|
        blocks_under(n).each do |b|
          names_under(b, mentioned)
          forwarded.each { |name| mentioned[name] = true } if bare_super?(b)
        end
      end
      owned.select { |n| mentioned.key?(n) }
    end

    # A literal block is a `BlockNode`, `->` is a `LambdaNode` and an
    # `END { }` is a `PostExecutionNode`. Every one of those bodies
    # outlives the frame that wrote it, so all of them box what they name.
    BLOCK_BODIES = [Prism::BlockNode, Prism::LambdaNode, Prism::PostExecutionNode].freeze

    def blocks_under(node, found = [])
      found << node if BLOCK_BODIES.any? { |k| node.is_a?(k) }
      node.compact_child_nodes.each { |c| blocks_under(c, found) }
      found
    end

    LOCAL_NODES = [
      Prism::LocalVariableReadNode, Prism::LocalVariableWriteNode,
      Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableOrWriteNode,
      Prism::LocalVariableAndWriteNode, Prism::LocalVariableTargetNode,
    ].freeze

    # Whether a body reaches for its call-site block. A block literal
    # written INSIDE it has its own, so only a bare `yield` or
    # `block_given?` counts -- and neither can appear in a nested `def`,
    # which ze0 refuses anyway.
    def uses_block?(node)
      return false if node.nil?
      return true if node.is_a?(Prism::YieldNode)
      # `super` forwards the caller's block whether or not the method
      # names one, so the signature has to carry it here too -- without
      # the parameter the trampoline releases it and it is gone.
      return true if node.is_a?(Prism::SuperNode) || node.is_a?(Prism::ForwardingSuperNode)
      return true if node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name == :block_given?

      node.compact_child_nodes.any? { |c| uses_block?(c) }
    end

    def names_under(node, found = {})
      found[node.name] = true if LOCAL_NODES.any? { |k| node.is_a?(k) }
      node.compact_child_nodes.each { |c| names_under(c, found) }
      found
    end

    # A bare call ze0 may lower as a DIRECT call to a body, skipping
    # dispatch.
    #
    # Only in a program with no classes. Once one exists, the name a bare
    # call resolves to is a run-time fact: `describe` calling `speak`
    # inside `Animal` must reach `Dog#speak` for a Dog, and deciding that
    # statically needs an override analysis ze0 does not have. Every call
    # in such a program takes the dynamic send, which is slower and right.
    def visible_def(name)
      return nil unless @classes.empty?

      @defs[Names::OBJECT][[name, false]]
    end

    # ---- functions ----

    # Lower `function` as a new scope, and answer it to the caller once the
    # body has left the stack.
    # The class ruby's visibility barrier compares an explicit receiver's
    # method against: the class of `self` where the site is written.
    #
    # In an instance method that is the enclosing class. In a class method
    # or a class body it is `Class` -- or `Module` -- because `self` there
    # IS the class object, and a class object is no kind of the class
    # whose instances a protected method belongs to.
    def caller_class_of(owner, self_is_class)
      return owner unless self_is_class

      @classes[owner]&.fetch(:kind) == "module" ? "Module" : "Class"
    end

    def in_scope(function, kind)
      @scopes.push(Scope.new(function, kind))
      yield
      @scopes.pop.f
    end

    def lower_def(definition)
      return lower_accessor(definition) if definition[:accessor]

      node = definition[:node]
      owner, singleton = definition[:owner], definition[:singleton]
      params = definition[:params]
      names = params.slot_names
      takes_block = definition[:block]
      body_sym = body_symbol_of(owner, node.name, singleton)
      arity = names.size + (takes_block ? 3 : 2)
      function = Clif::Function.new(body_sym, ["i64"] * arity, "i32")
      in_scope(function, :body) do
        scope.owner = owner
        scope.cref = definition[:cref]
        scope.caller_class = caller_class_of(owner, singleton)
        scope.definition = definition
        scope.catches_return = returns_travel?(node.body)
        scope.svars = mentions_svars?(node.body)
        scope.self_operand = Operand.new(f.args[0], false, false)
        scope.blk = f.args[names.size + 1] if takes_block
        scope.out = f.args.last
        prologue
        own = (names + [params.block].compact + node.locals).uniq
        boxed = captured_names(body_statements(node.body), own, names)
        own.each { |n| declare_local(n, boxed: boxed.include?(n)) }
        status = f.val("call #{f.import("zeo_rt_stack_check")}()")
        overflow, cont = f.label, f.label
        f.ins "brif #{status}, #{overflow}, #{cont}"
        f.switch(overflow)
        f.ins "return #{f.iconst("i32", 1)}"
        f.switch(cont)
        # After the recursion guard, which leaves without an epilogue.
        push_home if scope.catches_return
        bind_slots(params, names)
        unpack_destructures(params)
        bind_block_parameter(params.block) if params.block
        scope.frame_base = label_of(owner, node.name, singleton)
        enter_frame(scope.frame_label, node.location.start_line, node.location.end_line)
        value = lower_statements(node.body)
        move(value, out) unless f.terminated?
        f.ins "jump #{done_block}" unless f.terminated?
        epilogue
      end
      @program.add_function(label_of(owner, node.name, singleton), function)
      if params.plain?
        lower_trampoline(definition, names.size)
      else
        lower_bound_trampoline(definition, params, names.size)
      end
    end

    # An `attr_*`-generated accessor, which in ruby is ISEQ-LESS: it holds
    # no frame, appears in no backtrace, and its own wrong-arity raise is
    # reported at the caller's line. So there is no body function and no
    # frame push -- the trampoline is the whole method, an arity check and
    # one slot access (`clif/params.rs`'s `define_accessor`).
    #
    # The Rust emitter also writes a `REG_ACCESSOR_SLOT` row beside it, so
    # a call site caches the SLOT instead of this trampoline. ze0 does not:
    # the row names its class by ID, which a front end never learns. The
    # row is registration data and the method table still carries the
    # trampoline, so leaving it out costs a cache hit and answers the same.
    def lower_accessor(definition)
      owner, name, writer = definition[:owner], definition[:name], definition[:accessor] == :writer
      ivar = definition[:ivar]
      # An exception subclass's instances are the runtime's own
      # `RubyException`, which declares no slots at all: a slot write on
      # one is dropped. Its accessor reaches the name-keyed store, which
      # is what the Rust emitter falls back to for a native-backed class.
      keyed = native_backed?(owner)
      function = Clif::Function.new(trampoline_of(owner, name, false), ["i64"] * 5, "i32")
      in_scope(function, :trampoline) do
        recv, argv, argc, blk, into = f.args
        scope.rodata = f.val("symbol_value.i64 #{f.symbol("zeo_rodata")}") if keyed
        release_block_argument(blk)
        want = f.iconst("i64", writer ? 1 : 0)
        fits = f.val("icmp eq #{argc}, #{want}")
        go, wrong = f.label, f.label
        f.ins "brif #{fits}, #{go}, #{wrong}"
        f.switch(wrong)
        f.ins "return #{f.val("call #{f.import("zeo_rt_wrong_arity")}(#{argc}, #{want}, #{want})")}"
        f.switch(go)
        if keyed
          keyed_accessor(ivar, recv, argv, into, writer)
        else
          slot_accessor(@program.ivar_slot(owner, ivar), recv, argv, into, writer)
        end
      end
      @program.add_function(label_of(owner, name, false), function)
    end

    def slot_accessor(slot, recv, argv, into, writer)
      at = f.iconst("i64", slot)
      unless writer
        f.ins "call #{f.import("zeo_rt_ivar_get_slot")}(#{recv}, #{at}, #{into})"
        return f.ins("return #{f.iconst("i32", 0)}")
      end

      status_return(f.val("call #{f.import("zeo_rt_frozen_check")}(#{recv})"))
      # Two fresh references off the caller's borrowed argument: one moves
      # into the slot, one is the value the writer answers.
      retain_if_heap(argv)
      retain_if_heap(argv)
      copy(argv, into)
      f.ins "return #{f.val("call #{f.import("zeo_rt_ivar_set_slot")}(#{recv}, #{at}, #{argv})")}"
    end

    def keyed_accessor(ivar, recv, argv, into, writer)
      ptr, len = rodata_ref(ivar)
      box = f.iconst("i32", Capi::MAIN_BOX)
      unless writer
        return f.ins("return #{f.val("call #{f.import("zeo_rt_ivar_get_dyn")}(#{recv}, #{ptr}, #{len}, #{box}, #{into})")}")
      end

      # The set BORROWS its value and does its own frozen check, so the
      # answer takes the one fresh reference.
      status_return(f.val("call #{f.import("zeo_rt_ivar_set_dyn")}(#{recv}, #{ptr}, #{len}, #{box}, #{argv})"))
      retain_if_heap(argv)
      copy(argv, into)
      f.ins "return #{f.iconst("i32", 0)}"
    end

    # Whether instances of `owner` are a runtime type rather than a
    # generated object with slots, which a builtin superclass makes them.
    def native_backed?(owner)
      entry = @classes.fetch(owner)
      return false if entry[:kind] == "module"

      up = @program.superclass_of(owner)
      up != Names::OBJECT && (!@classes.key?(up) || native_backed?(up))
    end

    # Leave with the signal this status reports, or carry on. A trampoline
    # has no landing block of its own: the caller's does the unwinding.
    def status_return(status)
      out, cont = f.label, f.label
      f.ins "brif #{status}, #{out}, #{cont}"
      f.switch(out)
      f.ins "return #{f.iconst("i32", 1)}"
      f.switch(cont)
    end

    # The trampoline of a shape the runtime's binder has to route: it
    # builds the slot array, hands `argv` to `zeo_rt_bind_params`, and
    # passes one pointer per slot -- NULL where an optional was left out,
    # so the body runs its default.
    def lower_bound_trampoline(definition, params, n_slots)
      node = definition[:node]
      owner, singleton = definition[:owner], definition[:singleton]
      takes_block = definition[:block]
      function = Clif::Function.new(trampoline_of(owner, node.name, singleton), ["i64"] * 5, "i32")
      in_scope(function, :trampoline) do
        recv, argv, argc, blk, into = f.args
        scope.rodata = f.val("symbol_value.i64 #{f.symbol("zeo_rodata")}")
        desc = param_desc(params, node.name.to_s, label_of(owner, node.name, singleton), node)
        slots = n_slots.zero? ? nil : f.slot(Capi::SLOT_BYTES * n_slots)
        slots_at = slots ? addr_of(slots) : f.iconst("i64", 0)
        present = f.slot(8)
        status = f.val(
          "call #{f.import("zeo_rt_bind_params")}(#{addr_of(desc)}, #{argv}, #{argc}, " \
          "#{slots_at}, #{addr_of(present)})",
        )
        ok, bad = f.label, f.label
        f.ins "brif #{status}, #{bad}, #{ok}"
        f.switch(bad)
        # The binder leaves every slot nil on an error, so only the block
        # it was handed still needs releasing.
        release_block_argument(blk)
        f.ins "return #{f.iconst("i32", 1)}"
        f.switch(ok)
        release_block_argument(blk) unless takes_block
        bits = f.val("load.i64 notrap aligned #{addr_of(present)}")
        addresses = (0...n_slots).map do |i|
          at = i.zero? ? slots_at : f.stack_addr("#{slots}+#{i * Capi::SLOT_BYTES}")
          next at unless params.optional_slots.include?(i)

          # An absent optional is a null pointer, which is how the body
          # tells "left out" from "given nil".
          got = f.val("band #{bits}, #{f.iconst("i64", 1 << i)}")
          f.val("select #{f.val("icmp ne #{got}, #{f.iconst("i64", 0)}")}, #{at}, #{f.iconst("i64", 0)}")
        end
        handed = takes_block ? addresses + [blk] : addresses
        n_params = n_slots + (takes_block ? 3 : 2)
        body = f.callee(body_symbol_of(owner, node.name, singleton), ["i64"] * n_params, "i32")
        status = f.val("call #{body}(#{([recv] + handed + [into]).join(", ")})")
        # The slots hold the binder's owned copies; the body took its own.
        (0...n_slots).each do |i|
          at = i.zero? ? slots_at : f.stack_addr("#{slots}+#{i * Capi::SLOT_BYTES}")
          f.ins "call #{f.import("zeo_rt_release")}(#{at})"
        end
        f.ins "return #{status}"
      end
      @program.add_function("trampoline", function)
    end

    # Each slot's value into its local. An optional slot arrives as a NULL
    # pointer when the caller left it out, and the default expression runs
    # here rather than at the call -- which is what lets one default read
    # the parameter before it.
    def bind_slots(params, names)
      defaults = params.defaults.to_h
      names.each_with_index do |n, i|
        local = locals.fetch(n)
        argument = f.args[i + 1]
        unless defaults.key?(i)
          initialize_local(local, argument)
          next
        end

        given, absent, join = f.label, f.label, f.label
        f.ins "brif #{f.val("icmp ne #{argument}, #{f.iconst("i64", 0)}")}, #{given}, #{absent}"
        f.switch(given)
        initialize_local(local, argument)
        f.ins "jump #{join}"
        f.switch(absent)
        store_local(local, lower_expr(defaults[i]))
        f.ins "jump #{join}" unless f.terminated?
        f.switch(join)
      end
    end

    # `&b`: not a slot, but the block channel itself, which is nil when
    # the caller passed none. The body already owns the moved-in block, so
    # the local takes a reference of its own.
    def bind_block_parameter(name)
      local = locals.fetch(name)
      given, join = f.label, f.label
      f.ins "brif #{f.val("icmp ne #{scope.blk}, #{f.iconst("i64", 0)}")}, #{given}, #{join}"
      f.switch(given)
      initialize_local(local, scope.blk)
      f.ins "jump #{join}"
      f.switch(join)
    end

    # The `ValueFn` the runtime dispatches to: releases a block it was
    # handed, checks the count, and calls the body on the argument slots.
    def lower_trampoline(definition, arity)
      node = definition[:node]
      owner, singleton = definition[:owner], definition[:singleton]
      takes_block = definition[:block]
      function = Clif::Function.new(trampoline_of(owner, node.name, singleton), ["i64"] * 5, "i32")
      in_scope(function, :trampoline) do
        recv, argv, argc, blk, into = f.args
        scope.rodata = f.val("symbol_value.i64 #{f.symbol("zeo_rodata")}")
        # A body that uses a block takes it as a parameter and releases it
        # itself; one that does not must release it here, since the block
        # was moved in either way.
        release_block_argument(blk) unless takes_block
        n = f.iconst("i64", arity)
        fits = f.val("icmp eq #{argc}, #{n}")
        go, wrong = f.label, f.label
        f.ins "brif #{fits}, #{go}, #{wrong}"
        f.switch(wrong)
        file, file_len = rodata_ref(@file)
        label, label_len = rodata_ref(label_of(owner, node.name, singleton))
        line = f.iconst("i32", node.location.start_line)
        end_line = f.iconst("i32", node.location.end_line)
        f.ins "call #{f.import("zeo_rt_frame_push")}(#{file}, #{file_len}, #{label}, #{label_len}, #{line}, #{end_line})"
        release_block_argument(blk) if takes_block
        status = f.val("call #{f.import("zeo_rt_wrong_arity")}(#{argc}, #{n}, #{n})")
        f.ins "call #{f.import("zeo_rt_frame_pop")}()"
        f.ins "return #{status}"
        f.switch(go)
        args = (0...arity).map do |i|
          i.zero? ? argv : f.val("iadd.i64 #{argv}, #{f.iconst("i64", i * Capi::SLOT_BYTES)}")
        end
        n_params = arity + (takes_block ? 3 : 2)
        body = f.callee(body_symbol_of(owner, node.name, singleton), ["i64"] * n_params, "i32")
        handed = takes_block ? args + [blk] : args
        status = f.val("call #{body}(#{([recv] + handed + [into]).join(", ")})")
        f.ins "return #{status}"
      end
      @program.add_function("trampoline", function)
    end

    # A class or module body is its own function with the class as `self`,
    # called at the statement's position. A `def` inside it registers
    # statically and only leaves its name behind, which is what ruby
    # answers for one.
    def lower_class_body(entry, written)
      symbol = written[:symbol]
      node = written[:node]
      function = Clif::Function.new(symbol, ["i64", "i64"], "i32")
      in_scope(function, :class_body) do
        scope.owner = entry[:name]
        scope.cref = written[:cref]
        scope.caller_class = caller_class_of(entry[:name], true)
        scope.self_operand = Operand.new(f.args[0], false, false)
        scope.out = f.args[1]
        prologue
        scope.svars = mentions_svars?(written[:body])
        boxed = captured_names(written[:body], node.locals)
        node.locals.each { |n| declare_local(n, boxed: boxed.include?(n)) }
        # The label is the name as WRITTEN, not the path: ruby prints
        # `<class:C>` for a `C` nested in `M`.
        scope.frame_base = Names.body_label(node.name, entry[:kind])
        enter_frame(scope.frame_label, node.location.start_line, node.location.end_line)
        value = lower_statements(node.body)
        move(value, out) unless f.terminated?
        f.ins "jump #{done_block}" unless f.terminated?
        epilogue
      end
      @program.add_function(symbol, function)
    end

    # `class Foo ... end` in statement position: the class is already
    # registered, so this reads it and runs its body.
    def lower_class_statement(node)
      # The body found the statement, so the declaration pass named it:
      # the row it filed the node under is the answer, name and all.
      entry = @classes.values.find { |c| c[:bodies].any? { |b| b[:node].equal?(node) } }
      raise Unsupported.new(node, "a class nested inside another statement") if entry.nil?
      # Each `class Foo ... end` runs ITS body, so a reopen adds to the
      # class where the statement stands rather than all at once.
      written = entry[:bodies].find { |b| b[:node].equal?(node) }
      raise Unsupported.new(node, "a class nested inside another statement") if written.nil?

      # ruby makes the constant where the statement RUNS, so the row the
      # backend registered concealed is revealed here -- and one whose
      # statement never runs stays a NameError.
      f.ins "call #{f.import("zeo_rt_reveal_class")}(#{class_id(entry[:name])})"
      klass = class_value(entry[:name])
      result = f.slot
      body = f.callee(written[:symbol], ["i64", "i64"], "i32")
      status_check(f.val("call #{body}(#{borrow(klass)}, #{addr_of(result)})"))
      Operand.new(result, true, false)
    end

    # `class << obj` opens the object's SINGLETON class, which no row can
    # name: a singleton is minted per object at run time. So the body is
    # not lowered as a class body at all. Each `def` in it becomes
    # `obj.define_singleton_method(:name, ->(...) { })` -- the same shape
    # the emitter desugars this statement to -- and a `private` names the
    # methods below it on `obj.singleton_class`, which is how ruby spells
    # a private singleton method.
    #
    # The receiver is evaluated ONCE, so a side-effecting one runs the
    # number of times it is written.
    def lower_singleton_class(node)
      recv = lower_expr(node.expression)
      # Pooled up front: the receiver is read once per statement in the
      # body, and the frame is what releases it.
      borrow(recv)
      mode = "public"
      value = literal_nil
      body_statements(node.body).each do |s|
        raise Unsupported.new(s, "a statement in a `class << obj` body") unless s.is_a?(Prism::DefNode) ||
                                                                               visibility_verb?(s)

        if s.is_a?(Prism::DefNode)
          value = define_singleton(recv, s, mode)
          next
        end
        mode, value = singleton_visibility(recv, s, mode)
      end
      value
    end

    def visibility_verb?(node)
      node.is_a?(Prism::CallNode) && node.receiver.nil? && VISIBILITY.include?(node.name.to_s)
    end

    # One `def` in a `class << obj` body, installed on the object and
    # marked when the body is in a non-public mode.
    def define_singleton(recv, node, mode)
      send_value(recv, :define_singleton_method, [literal_symbol(node.name), method_proc(node)])
      mark_singleton(recv, node.name.to_s, mode) unless mode == "public"
      literal_symbol(node.name)
    end

    # A `private`/`public`/`protected` in a `class << obj` body: bare, it
    # is the mode the `def`s below it are written in; with names, it
    # retags those where it stands.
    def singleton_visibility(recv, node, mode)
      verb = node.name.to_s
      args = node.arguments&.arguments || []
      return [verb, literal_nil] if args.empty?

      value = literal_nil
      args.each do |a|
        if a.is_a?(Prism::DefNode)
          value = define_singleton(recv, a, verb)
          next
        end
        accessor_names(node, [a]).each { |n| mark_singleton(recv, n, verb) }
        value = lower_expr(a)
      end
      [mode, value]
    end

    # `obj.singleton_class.send(:private, :name)`, which is how ruby marks
    # one singleton method. It goes through `send` because `Module#private`
    # is itself private, so an explicit receiver would be refused.
    def mark_singleton(recv, name, verb)
      singleton = send_value(recv, :singleton_class)
      send_value(singleton, :send, [literal_symbol(verb), literal_symbol(name)])
    end

    # A lambda-shaped Proc over a `def`'s body, as an owned value.
    def method_proc(node)
      body, captures = lower_method_body(node)
      slot = f.slot
      copy(proc_new(body, captures, node, true), addr_of(slot))
      Operand.new(slot, true, false)
    end

    # Every unit's statements, in load order, as one function. A unit is a
    # run of statements from one file, so the same file comes back once
    # per `require_relative` written between its own statements.
    def lower_toplevel(units) = lower_top_scope(Names::TOPLEVEL, units)

    # A top-level scope as one function: `<main>`, or one deferred file
    # the run-time require runs. Both have their own file-isolated
    # locals and their own frame; only the name differs.
    def lower_top_scope(symbol, units)
      # A `def` with a ROW is installed before the program runs, so where
      # the statement stands it lowers to nothing. One WITHOUT a row --
      # `def obj.name`, whose object no compile can know -- is an ordinary
      # statement and stays.
      units = units.map do |file, run|
        [file, run.reject { |s| s.is_a?(Prism::DefNode) && @declared_defs[s.object_id] }]
      end
      function = Clif::Function.new(symbol, ["i64"], "i32")
      in_scope(function, :toplevel) do
        scope.out = f.args[0]
        prologue
        units.group_by(&:first).each { |file, runs| declare_unit(file, runs.flat_map(&:last)) }
        scope.frame_base = "<main>"
        enter_frame(scope.frame_label, 0, 0)
        # The top-level `self`, pooled for the frame.
        self_slot = f.slot
        f.ins "call #{f.import("zeo_rt_main_object")}(#{addr_of(self_slot)})"
        f.ins "call #{f.import("zeo_rt_pool_push")}(#{addr_of(self_slot)})"
        scope.self_operand = Operand.new(self_slot, false, false)
        units.each do |file, run|
          scope.locals = scope.locals_of(file)
          with_file(file) { hoist_pre_execution(run).each { |s| toplevel_statement(s) } }
        end
        store_nil(out)
        f.ins "jump #{done_block}"
        epilogue
      end
      @program.add_function(symbol, function)
    end

    # One file's top-level names, in their own table of slots. They are
    # all nil before the program runs, as the whole function's are.
    def declare_unit(file, statements)
      scope.locals = scope.locals_of(file)
      names = @unit_locals.fetch(file)
      boxed = captured_names(statements, names)
      names.each { |n| declare_local(n, boxed: boxed.include?(n)) }
    end

    # `BEGIN { }` runs before the rest of the file it is written in, in
    # the order the file writes them. It shares the top-level names, so
    # the statements lower where they are moved to and nowhere else.
    def hoist_pre_execution(statements)
      first, rest = statements.partition { |s| s.is_a?(Prism::PreExecutionNode) }
      first + rest
    end

    # `END { }` is `at_exit { }`: the body runs at exit, last registered
    # first. prism's node is not a block node, so it is dressed as one.
    def lower_end_block(node)
      block = EndBlock.new(node.statements, node.location)
      body, captures = lower_block(block)
      slot = f.slot
      dynamic_send(borrow(self_operand), :at_exit, [], addr_of(slot), explicit: false) do
        proc_new(body, captures, block, false)
      end
      Operand.new(slot, true, false)
    end

    def toplevel_statement(node)
      mark = f.val("call #{f.import("zeo_rt_pool_mark")}()")
      set_line(node)
      discard(lower_expr(node))
      f.ins "call #{f.import("zeo_rt_pool_reset")}(#{mark})"
    end

    # The rodata and symbol-table bases every function reads, and the two
    # blocks every status check can land in.
    def prologue
      scope.rodata = f.val("symbol_value.i64 #{f.symbol("zeo_rodata")}")
      scope.syms = f.val("symbol_value.i64 #{f.symbol("zeo_syms")}")
      scope.raise_block = f.label
      scope.done_block = f.label
      scope.exit_block, (scope.status,) = f.block(["i32"])
    end

    # `zeo_rt_frame_enter` fuses the frame push and the interrupt
    # checkpoint. A scope with its own `$~` splits them, because the svar
    # push has to stand between the two: the checkpoint can raise, and
    # the exit pops what the entry pushed.
    def enter_frame(label, line, end_line)
      file, file_len = rodata_ref(@file)
      label, label_len = rodata_ref(label)
      args = "#{file}, #{file_len}, #{label}, #{label_len}, " \
             "#{f.iconst("i32", line)}, #{f.iconst("i32", end_line)}"
      unless scope.svars
        return status_check(f.val("call #{f.import("zeo_rt_frame_enter")}(#{args})"))
      end

      f.ins "call #{f.import("zeo_rt_frame_push")}(#{args})"
      f.ins "call #{f.import("zeo_rt_svar_scope_push")}()"
      status_check(f.val("call #{f.import("zeo_rt_check_ints")}()"))
    end

    # The methods that WRITE `$~` without naming it. Names only, no
    # receiver: a false positive costs one dead scope push, and a false
    # negative leaks a match to the caller.
    SVAR_WRITERS = %i[
      =~ match match? scan sub sub! gsub gsub! split slice slice!
      index rindex partition rpartition start_with? end_with? grep grep_v ===
      last_match
    ].freeze

    SVAR_READS = [
      Prism::NumberedReferenceReadNode, Prism::BackReferenceReadNode, Prism::MatchWriteNode,
    ].freeze

    # Whether this scope can touch the `$~` family and so needs a slot of
    # its own. Blocks share their method's, so the walk goes through
    # them; a nested `def` has its own, and the walk stops there.
    def mentions_svars?(node)
      return node.any? { |n| mentions_svars?(n) } if node.is_a?(Array)
      return false if node.nil? || node.is_a?(Prism::DefNode)
      return true if SVAR_READS.any? { |k| node.is_a?(k) }
      return true if node.is_a?(Prism::CallNode) && SVAR_WRITERS.include?(node.name)

      case node
      when Prism::GlobalVariableReadNode, Prism::GlobalVariableWriteNode
        return true if node.name == :$~
      end
      node.compact_child_nodes.any? { |child| mentions_svars?(child) }
    end

    # A method activation a `return` written in a block it makes can
    # unwind to. `zeo_rt_return_targets_here` reads it, which is what
    # tells one activation of a recursive method from another.
    def push_home
      f.ins "call #{f.import("zeo_rt_home_push")}()"
    end

    # The shared exit: a status of 0 from `done`, 1 from `raise`, then the
    # locals released, the frame popped, and the status answered.
    def epilogue
      f.switch(done_block)
      f.ins "jump #{scope.exit_block}(#{f.iconst("i32", 0)})"
      f.switch(raise_block)
      fold_signal if scope.lambda? || scope.catches_return
      f.ins "jump #{scope.exit_block}(#{f.iconst("i32", 1)})"
      f.switch(scope.exit_block)
      scope.all_locals.each { |local| release_local(local) }
      release_block_argument(scope.blk) if scope.blk
      f.ins "call #{f.import("zeo_rt_frame_pop")}()"
      f.ins "call #{f.import("zeo_rt_svar_scope_pop")}()" if scope.svars
      f.ins "call #{f.import("zeo_rt_home_pop")}()" if scope.catches_return
      f.ins "return #{scope.status}"
    end

    # A signal this body answers folds into its own value; every other
    # one is a real unwind and carries on. A lambda answers the `return`
    # and the `break` written inside it, and a method answers a `return`
    # the runtime says is aimed at THIS activation -- asked while the
    # home is still on the stack.
    def fold_signal
      signal = f.val("call #{f.import("zeo_rt_signal_kind")}()")
      fold, normal = f.label, f.label
      mine = f.val("icmp eq #{signal}, #{f.iconst("i8", Capi::SIGNAL_RETURN)}")
      if scope.lambda?
        broke = f.val("icmp eq #{signal}, #{f.iconst("i8", Capi::SIGNAL_BREAK)}")
        f.ins "brif #{f.val("bor #{mine}, #{broke}")}, #{fold}, #{normal}"
      else
        ask = f.label
        f.ins "brif #{mine}, #{ask}, #{normal}"
        f.switch(ask)
        here = f.val("call #{f.import("zeo_rt_return_targets_here")}()")
        f.ins "brif #{here}, #{fold}, #{normal}"
      end
      f.switch(fold)
      f.val("call #{f.import("zeo_rt_signal_take")}(#{out})")
      f.ins "jump #{done_block}"
      f.switch(normal)
    end

    # Whether a `return` written under `node` travels to this body's
    # boundary as a signal: one inside a block leaves through the proc's
    # home, and one an `ensure` stands in front of goes the same way so
    # the clause runs first. A nested `def` or lambda catches its own.
    def returns_travel?(node, escaped = false)
      return false if node.nil?
      return escaped if node.is_a?(Prism::ReturnNode)
      return false if node.is_a?(Prism::DefNode) || node.is_a?(Prism::LambdaNode)

      escaped ||= node.is_a?(Prism::BlockNode) ||
                  (node.is_a?(Prism::BeginNode) && !node.ensure_clause.nil?)
      node.compact_child_nodes.any? { |child| returns_travel?(child, escaped) }
    end

    # Whether a `return` written in a block's body reaches out of it. The
    # proc holds the activation it unwinds to, and a dead one answers
    # LocalJumpError instead.
    def block_returns?(node)
      return false if node.nil?
      return true if node.is_a?(Prism::ReturnNode)
      return false if node.is_a?(Prism::DefNode) || node.is_a?(Prism::LambdaNode)

      node.compact_child_nodes.any? { |child| block_returns?(child) }
    end

    # A block literal as its own CLIF function, the runtime's `BlockFn`:
    # `(env, self, argv, argc, blk, out) -> i32`. Note the shape is NOT the
    # five-pointer trampoline's -- a block fn prepends `env` and takes its
    # `self` as a parameter, because `instance_exec` rebinds it per call.
    def lower_block(node, lambda_shape = false)
      lower_closure(node, lambda_shape: lambda_shape)
    end

    # The body of a `def` the declaration pass did not reach, as a closure
    # the runtime installs as a method. It is a method's scope, not a
    # block's: it binds strictly, sees none of the names around it, its
    # frame carries the method's own label, and its `blk` argument is the
    # block the INSTALLED method is called with, which a bare `yield`
    # reaches.
    def lower_method_body(node)
      lower_closure(node, lambda_shape: true, method: label_of(owner, node.name, false))
    end

    # The shared shape of both. `method` is the frame label when the body
    # is a method's, and nil for an ordinary block.
    def lower_closure(node, lambda_shape:, method: nil)
      params = block_params(node)
      names = params.slot_names
      # ruby spreads a single Array argument over a shape with real
      # positional structure; one bare parameter is ambiguous and never
      # splats (`clif/params.rs`'s `auto_splats`).
      auto_splat = !lambda_shape && auto_splats?(params)
      symbol = "zeo_blk_#{@blocks}"
      @blocks += 1
      function = Clif::Function.new(symbol, ["i64"] * 6, "i32")
      base, depth, own_owner, own_cref = scope.frame_base, scope.block_depth, owner, cref
      # A block's `self` is the enclosing scope's, so its barrier is too.
      # A body the runtime installs has neither.
      enclosing = [scope.caller_class, scope.dynamic_caller]
      # The enclosing names this block reads. Both ends read this list in
      # the same order, so the creation site's array and the body's
      # `ProcEnv` rows line up. A method body reads none of them.
      captures = method ? [] : block_captures(node, names)
      in_scope(function, method ? :body : :block) do
        scope.owner = own_owner
        scope.cref = own_cref
        # A body the runtime installs knows its own parameters, which a
        # bare `super` forwards, but not the class it will land on -- so
        # the `super` target comes off the frame stack instead.
        scope.definition = { params: params, node: node, singleton: false, runtime: true } if method
        scope.caller_class, inherited = enclosing
        scope.dynamic_caller = !method.nil? || inherited
        scope.lambda = lambda_shape && method.nil?
        scope.catches_return = !method.nil? && returns_travel?(node.body)
        scope.svars = !method.nil? && mentions_svars?(node.body)
        scope.frame_base = method || base
        scope.block_depth = method ? 0 : depth + 1
        env, slf, argv, argc, blk, into = f.args
        scope.env = env
        scope.self_operand = Operand.new(slf, false, false)
        scope.out = into
        prologue
        # A method body keeps the call-site block, because a bare `yield`
        # in it means the block the installed method was called with. A
        # block body can never reach one, so it releases it here.
        if method
          scope.blk = blk
        else
          release_block_argument(blk)
        end
        captures.each_with_index { |n, i| declare_captured(n, env, i) }
        own = (names + [params.block].compact + node.locals).uniq
        boxed = captured_names(body_statements(node.body), own, names)
        own.each { |n| declare_local(n, boxed: boxed.include?(n)) }
        push_home if scope.catches_return
        bind_block_params(params, names, argv, argc, node, auto_splat, lambda_shape)
        unpack_destructures(params)
        enter_frame(scope.frame_label, node.location.start_line, node.location.end_line)
        scope.redo_block = f.label
        f.ins "jump #{scope.redo_block}"
        f.switch(scope.redo_block)
        value = lower_statements(node.body)
        move(value, out) unless f.terminated?
        f.ins "jump #{done_block}" unless f.terminated?
        epilogue
      end
      @program.add_function(symbol, function)
      [symbol, captures]
    end

    # The names this block reads out of the scope that wrote it, sorted so
    # the order is the same on both sides of the `ProcEnv`.
    def block_captures(node, names)
      own = names + node.locals
      read = names_under(node).keys + bare_super_names(node)
      (read - own).select { |n| locals.key?(n) }.sort
    end

    # A bare `super` written in a block forwards the enclosing method's
    # parameters by their current values, without naming one of them, so
    # the block has to carry them even though nothing reads them.
    def bare_super_names(node)
      return [] unless bare_super?(node)

      definition = enclosing_definition
      return [] if definition.nil?

      definition[:params].slot_names
    end

    # A bare `super` this block would run: one in a nested `def` belongs
    # to that `def`, and a nested block carries its own.
    def bare_super?(node)
      return true if node.is_a?(Prism::ForwardingSuperNode)
      return false if node.is_a?(Prism::DefNode)

      node.compact_child_nodes.any? { |c| bare_super?(c) }
    end

    # The CALL-SITE block, moved in and so this body's to release.
    def release_block_argument(blk)
      has = f.val("icmp ne #{blk}, #{f.iconst("i64", 0)}")
      yes, no = f.label, f.label
      f.ins "brif #{has}, #{yes}, #{no}"
      f.switch(yes)
      f.ins "call #{f.import("zeo_rt_release")}(#{blk})"
      f.ins "jump #{no}"
      f.switch(no)
    end

    # Ruby's block binding is the runtime's, not a copy of it: lenient
    # positionals, auto-splat of a single Array argument when the shape has
    # real positional structure, and a lambda's strict arity.
    #
    # The binder reads a `ParamDescC`, which the Rust emitter writes into
    # rodata. ze0 cannot: the struct holds POINTERS, and a rodata blob a
    # sidecar carries as bytes has nowhere to put a relocation. So the
    # struct is built in a stack slot instead, which works because the
    # binder only reads it for the length of the call.

    # ruby spreads a single Array argument over a block whose shape has
    # real positional structure; one bare parameter is ambiguous and never
    # splats (`clif/params.rs`'s `auto_splats`).
    def auto_splats?(params)
      lead, opt, post = params.required.size, params.optional.size, params.post.size
      ambiguous = lead == 1 && opt.zero? && post.zero? && params.rest.nil?
      !ambiguous && (lead + post > 0 || opt > 1)
    end

    def bind_block_params(params, names, argv, argc, node, auto_splat, lambda_shape)
      return if names.empty?

      desc = param_desc(params, "block", scope.frame_label, node)
      slots = f.slot(Capi::SLOT_BYTES * names.size)
      present = f.slot(8)
      bits = auto_splat ? Capi::BLOCK_BIND_AUTO_SPLAT : 0
      bits |= Capi::BLOCK_BIND_LAMBDA if lambda_shape
      flags = f.iconst("i8", bits)
      status_check(f.val(
        "call #{f.import("zeo_rt_bind_block_params")}(#{addr_of(desc)}, #{flags}, #{argv}, #{argc}, " \
        "#{addr_of(slots)}, #{addr_of(present)})",
      ))
      present_bits = f.val("load.i64 notrap aligned #{addr_of(present)}")
      defaults = params.defaults.to_h
      # The binder writes an owned value into every bound slot, which the
      # local takes as it is; an unbound optional runs its default here.
      names.each_with_index do |n, i|
        from = i.zero? ? addr_of(slots) : f.stack_addr("#{slots}+#{i * Capi::SLOT_BYTES}")
        local = locals.fetch(n)
        unless defaults.key?(i)
          take_bound_slot(local, from)
          next
        end

        given, absent, join = f.label, f.label, f.label
        got = f.val("band #{present_bits}, #{f.iconst("i64", 1 << i)}")
        f.ins "brif #{f.val("icmp ne #{got}, #{f.iconst("i64", 0)}")}, #{given}, #{absent}"
        f.switch(given)
        take_bound_slot(local, from)
        f.ins "jump #{join}"
        f.switch(absent)
        store_local(local, lower_expr(defaults[i]))
        f.ins "jump #{join}" unless f.terminated?
        f.switch(join)
      end
    end

    # A slot the binder owns, taken by the local: a plain slot copies the
    # bytes as they are, a cell moves them in.
    def take_bound_slot(local, from)
      if local.boxed?
        f.ins "call #{f.import("zeo_rt_cell_store")}(#{cell_of(local)}, #{from})"
      else
        copy(from, addr_of(local.slot))
      end
    end

    # A `zeo_abi::abi::ParamDescC` on the stack, and the `KwParamC` rows it
    # points at. Offsets follow the structs' declaration order under
    # `repr(C)`; the binder reads both only for the length of the call.
    def param_desc(params, name, label, node)
      kws, n_kws = keyword_rows(params.keywords)
      slot = f.slot(PARAM_DESC_BYTES)
      at = addr_of(slot)
      put = ->(off, value) { f.ins "store notrap aligned #{value}, #{at}#{off.zero? ? "" : "+#{off}"}" }
      put.call(0, f.iconst("i32", params.required.size))
      put.call(4, f.iconst("i32", params.optional.size))
      put.call(8, f.iconst("i32", params.post.size))
      put.call(12, f.iconst("i8", star_of(params.rest)))
      put.call(13, f.iconst("i8", star_of(params.kwrest)))
      put.call(14, f.iconst("i8", params.no_keywords ? 1 : 0))
      put.call(15, f.iconst("i8", 0))
      put.call(16, kws)
      put.call(24, n_kws)
      [[32, name], [48, @file], [64, label]].each do |off, text|
        ptr, len = rodata_ref(text)
        put.call(off, ptr)
        put.call(off + 8, len)
      end
      put.call(80, f.iconst("i32", node.location.start_line))
      put.call(84, f.iconst("i32", node.location.end_line))
      slot
    end

    PARAM_DESC_BYTES = 88
    KW_PARAM_BYTES = 24

    def star_of(star)
      return Capi::PARAM_STAR_NONE if star.nil?

      star.named? ? Capi::PARAM_STAR_NAMED : Capi::PARAM_STAR_ANON
    end

    def keyword_rows(keywords)
      return [f.iconst("i64", 0), f.iconst("i64", 0)] if keywords.empty?

      slot = f.slot(KW_PARAM_BYTES * keywords.size)
      at = addr_of(slot)
      keywords.each_with_index do |kw, i|
        off = i * KW_PARAM_BYTES
        ptr, len = rodata_ref(kw.name.to_s)
        f.ins "store notrap aligned #{ptr}, #{at}#{off.zero? ? "" : "+#{off}"}"
        f.ins "store notrap aligned #{len}, #{at}+#{off + 8}"
        f.ins "store notrap aligned #{f.iconst("i8", kw.required ? 1 : 0)}, #{at}+#{off + 16}"
      end
      [at, f.iconst("i64", keywords.size)]
    end

    # ---- statements ----

    # The statements of a body. A `def` or block written with its own
    # `rescue` clause carries a `BeginNode` here instead of a list, and it
    # lowers as the one statement it is.
    def body_statements(node)
      return [] if node.nil?
      return [node] if node.is_a?(Prism::BeginNode)

      node.body
    end

    # The value of the last statement; every other one is discarded.
    def lower_statements(node)
      body = body_statements(node)
      return literal_nil if body.empty?

      value = nil
      body.each_with_index do |s, i|
        discard(value) if value
        set_line(s)
        value = lower_expr(s)
        break if f.terminated? && i < body.size - 1
      end
      value
    end

    def set_line(node)
      f.ins "call #{f.import("zeo_rt_set_line")}(#{f.iconst("i32", node.location.start_line)})"
    end

    # ---- expressions ----

    def lower_expr(node)
      case node
      when Prism::IntegerNode then literal_int(node)
      when Prism::FloatNode then literal_float(node.value)
      when Prism::StringNode then literal_string(node.unescaped)
      when Prism::NilNode then literal_nil
      when Prism::TrueNode then literal_bool(1)
      when Prism::FalseNode then literal_bool(0)
      when Prism::SymbolNode then literal_symbol(node.unescaped)
      when Prism::RegularExpressionNode then literal_regexp(node)
      when Prism::InterpolatedRegularExpressionNode then interpolated_regexp(node)
      when Prism::InterpolatedSymbolNode then interpolated_symbol(node)
      when Prism::RationalNode then literal_rational(node)
      when Prism::ImaginaryNode then literal_imaginary(node)
      when Prism::SourceFileNode then literal_string(@file)
      when Prism::SourceLineNode then literal_fixnum(node.location.start_line)
      when Prism::SourceEncodingNode then source_encoding
      when Prism::InterpolatedStringNode then interpolated_string(node)
      when Prism::ArrayNode then array_literal(node)
      when Prism::HashNode then hash_literal(node)
      when Prism::RangeNode then range_literal(node)
      when Prism::LocalVariableReadNode then local_read(node)
      # `it` names the block's one parameter, which `block_params` gave a
      # slot under that name.
      when Prism::ItLocalVariableReadNode
        read_local(locals.fetch(:it) { raise Unsupported.new(node, "an it outside a block") })
      when Prism::LocalVariableWriteNode then local_write(node)
      when Prism::MultiWriteNode then multi_write(node)
      when Prism::LocalVariableOperatorWriteNode, Prism::InstanceVariableOperatorWriteNode,
           Prism::ClassVariableOperatorWriteNode,
           Prism::GlobalVariableOperatorWriteNode, Prism::IndexOperatorWriteNode,
           Prism::CallOperatorWriteNode then operator_write(node)
      when Prism::LocalVariableOrWriteNode, Prism::InstanceVariableOrWriteNode,
           Prism::ClassVariableOrWriteNode,
           Prism::GlobalVariableOrWriteNode, Prism::IndexOrWriteNode,
           Prism::CallOrWriteNode then conditional_write(node, false)
      when Prism::LocalVariableAndWriteNode, Prism::InstanceVariableAndWriteNode,
           Prism::ClassVariableAndWriteNode,
           Prism::GlobalVariableAndWriteNode, Prism::IndexAndWriteNode,
           Prism::CallAndWriteNode then conditional_write(node, true)
      when Prism::GlobalVariableReadNode then global_read(node)
      when Prism::GlobalVariableWriteNode then global_write(node)
      when Prism::NumberedReferenceReadNode then last_match(Capi::LAST_MATCH_GROUP, node.number)
      when Prism::BackReferenceReadNode then back_reference(node)
      when Prism::MatchWriteNode then lower_match_write(node)
      when Prism::InstanceVariableReadNode then ivar_read(node)
      when Prism::InstanceVariableWriteNode then ivar_write(node)
      when Prism::ClassVariableReadNode then cvar_read(node)
      when Prism::ClassVariableWriteNode then cvar_write(node, lower_expr(node.value))
      when Prism::ConstantReadNode then constant_read(node)
      when Prism::ConstantWriteNode then constant_write(node)
      when Prism::ConstantPathWriteNode then constant_path_write(node)
      when Prism::ConstantPathNode then constant_path_read(node)
      when Prism::AndNode then and_or(node.left, node.right, true)
      when Prism::OrNode then and_or(node.left, node.right, false)
      when Prism::CaseNode then lower_case(node)
      when Prism::CaseMatchNode then lower_case_match(node)
      when Prism::MatchPredicateNode then lower_match_predicate(node)
      when Prism::MatchRequiredNode then lower_match_required(node)
      when Prism::LambdaNode then lower_lambda(node)
      when Prism::ClassNode, Prism::ModuleNode then lower_class_statement(node)
      when Prism::SingletonClassNode then lower_singleton_class(node)
      when Prism::DefinedNode then lower_defined(node)
      when Prism::DefNode then declared_def(node)
      when Prism::SelfNode then Operand.new(self_operand.at, false, self_operand.immediate)
      when Prism::CallNode then lower_call(node)
      when Prism::IfNode, Prism::UnlessNode then lower_conditional(node)
      when Prism::WhileNode then lower_while(node.predicate, node.statements, false)
      when Prism::UntilNode then lower_while(node.predicate, node.statements, true)
      when Prism::ReturnNode then lower_return(node)
      when Prism::YieldNode then lower_yield(node)
      when Prism::SuperNode then lower_super(node, node.arguments&.arguments || [])
      when Prism::ForwardingSuperNode then lower_super(node, nil)
      when Prism::NextNode then lower_next(node)
      when Prism::BreakNode then lower_break(node)
      when Prism::RedoNode then lower_redo(node)
      when Prism::ForNode then lower_for(node)
      when Prism::BeginNode then lower_begin(node)
      when Prism::RescueModifierNode then lower_rescue_modifier(node)
      when Prism::AliasMethodNode then lower_alias_statement(node)
      when Prism::PostExecutionNode then lower_end_block(node)
      when Prism::PreExecutionNode then lower_statements(node.statements)
      when Prism::AliasGlobalVariableNode then lower_global_alias(node)
      when Prism::ParenthesesNode then lower_statements(node.body)
      when Prism::StatementsNode then lower_statements(node)
      when Prism::ElseNode then lower_statements(node.statements)
      else raise Unsupported.new(node)
      end
    end

    # An Integer that fits the inline payload is two stores; one past it
    # is built from its baked digits, and the runtime demotes it back to
    # the inline form whenever it fits again.
    def literal_int(node)
      value = node.value
      return literal_bignum(value) unless value.bit_length < 64

      literal_fixnum(value)
    end

    def literal_fixnum(value)
      slot = f.slot
      at = addr_of(slot)
      f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_INT)}, #{at}"
      f.ins "store notrap aligned #{f.iconst("i64", value)}, #{at}+8"
      Operand.new(slot, false, true)
    end

    def literal_bignum(value)
      slot = f.slot
      digits, n = digit_array(value)
      f.ins "call #{f.import("zeo_rt_int_digits")}(#{sign_of(value)}, #{digits}, #{n}, #{addr_of(slot)})"
      Operand.new(slot, true, false)
    end

    # `3r` and `1.5r`. Prism pre-rationalizes the decimal form, so both
    # arrive as a numerator and a denominator, and the denominator is
    # positive by syntax.
    def literal_rational(node)
      slot = f.slot
      num, num_n = digit_array(node.numerator)
      den, den_n = digit_array(node.denominator)
      f.ins "call #{f.import("zeo_rt_rational_digits")}(#{sign_of(node.numerator)}, " \
            "#{num}, #{num_n}, #{den}, #{den_n}, #{addr_of(slot)})"
      Operand.new(slot, true, false)
    end

    # `4i` is `Complex(0, 4)` over the numeric written in front of it.
    def literal_imaginary(node)
      slot = f.slot
      f.ins "call #{f.import("zeo_rt_complex_lit")}(#{borrow(lower_expr(node.numeric))}, #{addr_of(slot)})"
      Operand.new(slot, true, false)
    end

    def sign_of(value) = f.iconst("i8", value.negative? ? 1 : 0)

    # An Integer's magnitude as the u32 digits the runtime reads,
    # least-significant first. The callee only reads them for the length
    # of the call, so a stack slot holds them.
    def digit_array(value)
      cid_array(value.abs.digits(1 << 32).map { |d| f.iconst("i32", d) })
    end

    # A Float's bits as an i64 store: the same 8 bytes, with no float
    # literal in the text.
    def literal_float(value)
      slot = f.slot
      at = addr_of(slot)
      bits = [value].pack("G").unpack1("q>")
      f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_FLOAT)}, #{at}"
      f.ins "store notrap aligned #{f.iconst("i64", bits)}, #{at}+8"
      Operand.new(slot, false, true)
    end

    # Under `# frozen_string_literal: true` the entry interns, so two
    # equal literals are ONE frozen object; otherwise each evaluation
    # mints a fresh string that BORROWS the rodata bytes until a
    # mutation promotes the buffer.
    def literal_string(bytes)
      slot = f.slot
      ptr, len = rodata_ref(bytes)
      entry = @program.frozen_string_literal ? "zeo_rt_str_lit" : "zeo_rt_str_lit_ro"
      f.ins "call #{f.import(entry)}(#{ptr}, #{len}, #{f.iconst("i8", Capi::UTF8)}, #{addr_of(slot)})"
      Operand.new(slot, true, false)
    end

    def literal_nil
      slot = f.slot
      store_nil(addr_of(slot))
      Operand.new(slot, false, true)
    end

    # A Symbol is its interned id, read from the `zeo_syms` slot the
    # program's startup fills.
    def literal_symbol(name)
      slot = f.slot
      at = addr_of(slot)
      store_nil(at)
      f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_SYMBOL)}, #{at}"
      f.ins "store notrap aligned #{sym_id(name)}, #{at}+8"
      Operand.new(slot, false, true)
    end

    # The id of `name` in the symbol table, as an i32.
    def sym_id(name)
      sym = @program.sym(name)
      f.val("load.i32 notrap aligned #{syms}#{sym.zero? ? "" : "+#{sym * 4}"}")
    end

    def literal_bool(bit)
      slot = f.slot
      at = addr_of(slot)
      f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_BOOL)}, #{at}"
      f.ins "store notrap aligned #{f.iconst("i8", bit)}, #{at}+8"
      Operand.new(slot, false, true)
    end

    # A `"a#{b}c"`: a fresh empty String, then each piece appended. The
    # destination goes to the pool at CREATION, not at the end, because an
    # interpolated piece runs `to_s` and can raise.
    def interpolated_string(node)
      slot = f.slot
      at = addr_of(slot)
      zero = f.iconst("i64", 0)
      f.ins "call #{f.import("zeo_rt_str_new")}(#{zero}, #{zero}, #{f.iconst("i8", Capi::UTF8)}, #{at})"
      f.ins "call #{f.import("zeo_rt_pool_push")}(#{at})"
      node.parts.each { |part| append_part(at, part) }
      Operand.new(slot, false, false)
    end

    def append_part(at, part)
      case part
      when Prism::StringNode
        return if part.unescaped.empty?

        ptr, len = rodata_ref(part.unescaped)
        f.ins "call #{f.import("zeo_rt_str_append_lit")}(#{at}, #{ptr}, #{len})"
      when Prism::EmbeddedStatementsNode
        append_value(at, lower_statements(part.statements))
      when Prism::EmbeddedVariableNode
        append_value(at, lower_expr(part.variable))
      # Adjacent literals (`"a" "b"`, or one written over two lines) are
      # ONE string, and prism nests them a level deeper.
      when Prism::InterpolatedStringNode
        part.parts.each { |inner| append_part(at, inner) }
      else raise Unsupported.new(part, "an interpolated piece of that shape")
      end
    end

    def append_value(at, value)
      status_check(f.val("call #{f.import("zeo_rt_str_append_value")}(#{at}, #{borrow(value)})"))
    end

    # `[a, b]`: the array is pooled at creation, so an element that raises
    # mid-build strands nothing. Each element is HANDED OVER -- the array
    # takes the reference.
    def array_literal(node)
      slot = f.slot
      at = addr_of(slot)
      f.ins "call #{f.import("zeo_rt_array_new")}(#{f.iconst("i64", node.elements.size)}, #{at})"
      f.ins "call #{f.import("zeo_rt_pool_push")}(#{at})"
      node.elements.each do |e|
        # `[*xs]` spreads through ruby's `to_a` rule, which the runtime
        # does; anything else is one element.
        unless e.is_a?(Prism::SplatNode)
          f.ins "call #{f.import("zeo_rt_array_push")}(#{at}, #{hand_over(lower_expr(e))})"
          next
        end
        raise Unsupported.new(e, "an anonymous splat") if e.expression.nil?

        status_check(f.val(
          "call #{f.import("zeo_rt_array_push_splat")}(#{at}, #{borrow(lower_expr(e.expression))})",
        ))
      end
      Operand.new(slot, false, false)
    end

    def hash_literal(node)
      slot = f.slot
      at = addr_of(slot)
      f.ins "call #{f.import("zeo_rt_hash_new")}(#{at})"
      f.ins "call #{f.import("zeo_rt_pool_push")}(#{at})"
      node.elements.each do |e|
        # `{**h}` merges h's pairs in place, through ruby's `to_hash`
        # rule. `**nil` is the "no keywords" spelling and adds nothing.
        if e.is_a?(Prism::AssocSplatNode)
          # A bare `**` forwards the anonymous keyword rest parameter.
          from = e.value ? lower_expr(e.value) : read_local(locals.fetch(:**))
          status_check(f.val(
            "call #{f.import("zeo_rt_kw_splat_into")}(#{at}, #{borrow(from)})",
          ))
          next
        end
        raise Unsupported.new(e, "a hash element of that shape") unless e.is_a?(Prism::AssocNode)

        key = hand_over(lower_expr(e.key))
        value = hand_over(lower_expr(e.value))
        status_check(f.val("call #{f.import("zeo_rt_hash_set")}(#{at}, #{key}, #{value})"))
      end
      Operand.new(slot, false, false)
    end

    # `a..b`, `a...b`, and either end left out. Both ends go to the pool
    # before either is handed over: lowering the second can raise while the
    # first is still owned here.
    def range_literal(node)
      ends = [node.left, node.right].map do |n|
        next if n.nil?

        value = lower_expr(n)
        borrow(value)
        value
      end
      addrs = ends.map { |v| v ? hand_over(v) : f.iconst("i64", 0) }
      slot = f.slot
      excl = f.iconst("i8", node.exclude_end? ? 1 : 0)
      status_check(f.val(
        "call #{f.import("zeo_rt_range_new")}(#{addrs[0]}, #{addrs[1]}, #{excl}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # ---- assignment to a name that is also read ----

    # `x += 1`, `x ||= 1` and `x &&= 1` are a read, an operation and a
    # write of the same name, so each form is written once and asks the
    # node which pair of halves it names.
    def target_of(node)
      case node
      when Prism::IndexOrWriteNode, Prism::IndexAndWriteNode, Prism::IndexOperatorWriteNode
        return index_target(node)
      when Prism::CallOrWriteNode, Prism::CallAndWriteNode, Prism::CallOperatorWriteNode
        return call_target(node)
      end

      name = node.name
      case node
      when Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableOrWriteNode,
           Prism::LocalVariableAndWriteNode
        local = locals.fetch(name) { raise Unsupported.new(node, "the local #{name} has no slot") }
        Target.new(-> { read_local(local) }, ->(v) { store_local(local, v) })
      when Prism::InstanceVariableOperatorWriteNode, Prism::InstanceVariableOrWriteNode,
           Prism::InstanceVariableAndWriteNode
        Target.new(-> { ivar_load(ivar_key(name)) }, ->(v) { store_ivar(ivar_key(name), v) })
      when Prism::ClassVariableOperatorWriteNode, Prism::ClassVariableOrWriteNode,
           Prism::ClassVariableAndWriteNode
        # `@@x ||= v` is the one read that tolerates an unassigned name.
        lenient = node.is_a?(Prism::ClassVariableOrWriteNode)
        Target.new(-> { cvar_read(node, lenient: lenient) }, ->(v) { cvar_write(node, v) })
      else
        Target.new(-> { global_load(name.to_s) }, ->(v) { store_global(name.to_s, v) })
      end
    end

    # `h[k] ||= v` and `x.y ||= v` read and write through a send, and the
    # receiver and the index are evaluated ONCE: both halves close over
    # the operands the pool is already holding.
    def index_target(node)
      recv = lower_expr(node.receiver)
      borrow(recv)
      args = (node.arguments&.arguments || []).map { |a| lower_expr(a) }
      args.each { |a| borrow(a) }
      Target.new(
        -> { send_value(recv, :[], args) },
        ->(v) { send_value(recv, :[]=, args + [v]) },
      )
    end

    def call_target(node)
      raise Unsupported.new(node, "a safe navigation write") if safe_navigation?(node)

      recv = lower_expr(node.receiver)
      borrow(recv)
      Target.new(
        -> { send_value(recv, node.read_name, []) },
        ->(v) { send_value(recv, node.write_name, [v]) },
      )
    end

    # An ordinary send with no keywords and no block, as an owned value.
    def send_value(recv, name, operands = [])
      slot = f.slot
      dynamic_send(borrow(recv), name, operands, addr_of(slot))
      Operand.new(slot, true, false)
    end

    def operator_write(node)
      target = target_of(node)
      name = node.binary_operator
      lhs = target.read.call
      rhs = lower_expr(node.value)
      target.write.call(inline_binary?(name) ? binary(name, lhs, rhs) : operator_send(name, lhs, rhs))
    end

    def operator_send(name, lhs, rhs)
      slot = f.slot
      dynamic_send(borrow(lhs), name, [rhs], addr_of(slot))
      Operand.new(slot, true, false)
    end

    # `x ||= v` answers `x` when it is truthy and never writes; `x &&= v`
    # is the same with the arms the other way round.
    def conditional_write(node, conjunction)
      target = target_of(node)
      current = target.read.call
      truth = truthy(current)
      result = f.slot
      keep, assign, join = f.label, f.label, f.label
      f.ins "brif #{truth}, #{conjunction ? assign : keep}, #{conjunction ? keep : assign}"
      f.switch(keep)
      arm(current, result, join)
      f.switch(assign)
      arm(target.write.call(lower_expr(node.value)), result, join)
      f.switch(join)
      Operand.new(result, true, false)
    end

    # ---- class variables ----
    #
    # The runtime keys storage by ONE class id, so the compile has to name
    # the class ruby's own lookup would have stopped at.

    # The class a `@@name` belongs to: the HIGHEST ancestor this program
    # declares whose source names it. That is where ruby's lookup stops,
    # so a subclass writing an inherited name writes the one slot both
    # share -- `Sub.bump` doing `@@total += 10` moves `Counter`'s.
    # The storage key drops the sigil, which is what the runtime puts back
    # for `class_variables` and for a NameError's message.
    def cvar_key(node) = node.name.to_s.delete_prefix("@@")

    def cvar_owner(node, name)
      if owner == Names::OBJECT
        raise Unsupported.new(node, "a class variable outside a class or module body")
      end

      chain = []
      at = owner
      while @classes.key?(at)
        chain << at
        at = @classes[at][:superclass]
      end
      chain.reverse.find { |c| @classes[c][:cvars].include?(name) } || owner
    end

    # A read. `lenient` is the `||=` half alone: every other read of a
    # name nobody assigned is ruby's NameError.
    def cvar_read(node, lenient: false)
      name = cvar_key(node)
      cid = class_id(cvar_owner(node, name))
      nptr, nlen = rodata_ref(name)
      slot = f.slot
      entry = lenient ? "zeo_rt_cvar_get" : "zeo_rt_cvar_get_checked"
      call = "call #{f.import(entry)}(#{cid}, #{nptr}, #{nlen}, #{addr_of(slot)})"
      lenient ? f.ins(call) : status_check(f.val(call))
      Operand.new(slot, true, false)
    end

    def cvar_write(node, value)
      name = cvar_key(node)
      cid = class_id(cvar_owner(node, name))
      nptr, nlen = rodata_ref(name)
      status_check(f.val("call #{f.import("zeo_rt_cvar_set")}(#{cid}, #{nptr}, #{nlen}, #{borrow(value)})"))
      Operand.new(value.at, false, value.immediate)
    end

    # ---- globals, constants and instance variables ----

    # Never assigned is nil, ruby's rule, so the read cannot fail.
    # `$~` is not a global at all: it names the last-match slot, which is
    # frame-local and holds every one of `$1`, `$&` and their kin.
    def global_read(node)
      return last_match(Capi::LAST_MATCH_DATA) if node.name == :$~

      global_load(node.name.to_s)
    end

    # `$&`, `` $` ``, `$'` and `$+`: one node kind, told apart by name.
    BACK_REFERENCES = {
      "$&" => [Capi::LAST_MATCH_GROUP, 0],
      "$`" => [Capi::LAST_MATCH_PRE, 0],
      "$'" => [Capi::LAST_MATCH_POST, 0],
      "$+" => [Capi::LAST_MATCH_LAST_GROUP, 0],
    }.freeze

    def back_reference(node)
      kind, n = BACK_REFERENCES.fetch(node.name.to_s) do
        raise Unsupported.new(node, "the `#{node.name}` back reference")
      end
      last_match(kind, n)
    end

    # One read off the last-match slot. It answers nil where nothing has
    # matched, so there is nothing to check and nothing to raise.
    def last_match(kind, number = 0)
      slot = f.slot
      f.ins "call #{f.import("zeo_rt_last_match_ref")}(#{f.iconst("i8", kind)}, " \
            "#{f.iconst("i64", number)}, #{addr_of(slot)})"
      Operand.new(slot, true, false)
    end

    # `/(?<year>\d+)/ =~ text` binds each named group to a local of that
    # name. The match is an ordinary `=~`, which is what records `$~`,
    # and each name then reads its own group out of the MatchData -- nil
    # where the match failed, so a miss leaves plain nils behind.
    def lower_match_write(node)
      result = f.slot
      move(lower_expr(node.call), addr_of(result))
      node.targets.each do |target|
        unless target.is_a?(Prism::LocalVariableTargetNode)
          raise Unsupported.new(target, "a named capture bound to that shape")
        end

        store_local(local(target), named_capture(target.name.to_s))
      end
      Operand.new(result, true, false)
    end

    def named_capture(name)
      data = last_match(Capi::LAST_MATCH_DATA)
      slot = f.slot
      store_nil(addr_of(slot))
      matched = f.val("icmp ne #{tag_of(borrow(data))}, #{f.iconst("i8", Capi::TAG_NIL)}")
      read, join = f.label, f.label
      f.ins "brif #{matched}, #{read}, #{join}"
      f.switch(read)
      dynamic_send(borrow(data), :[], [literal_symbol(name)], addr_of(slot))
      f.ins "jump #{join}"
      f.switch(join)
      Operand.new(slot, true, false)
    end

    def global_load(name)
      slot = f.slot
      ptr, len = rodata_ref(name)
      f.ins "call #{f.import("zeo_rt_gvar_get")}(#{f.iconst("i32", Capi::MAIN_BOX)}, #{ptr}, #{len}, #{addr_of(slot)})"
      Operand.new(slot, true, false)
    end

    # The table clones the value, so the operand keeps its own reference
    # and the assignment answers it. A read-only global raises.
    def global_write(node)
      store_global(node.name.to_s, lower_expr(node.value))
    end

    def store_global(name, value)
      at = borrow(value)
      ptr, len = rodata_ref(name)
      status_check(f.val(
        "call #{f.import("zeo_rt_gvar_assign")}(#{f.iconst("i32", Capi::MAIN_BOX)}, #{ptr}, #{len}, #{at})",
      ))
      Operand.new(value.at, false, value.immediate)
    end

    # Name-keyed, not slot-keyed: only a generated accessor names a slot,
    # and it knows its class. The name goes WITHOUT its `@`, which is the
    # spelling `ClassDesc.ivar_names` holds -- pass `@x` and the write
    # misses the declared slot, lands in the invented table, and
    # `instance_variables` answers `:@@x`.
    def ivar_read(node)
      ivar_load(ivar_key(node.name))
    end

    def ivar_key(name) = name.to_s.delete_prefix("@")

    def ivar_load(name)
      slot = f.slot
      ptr, len = rodata_ref(name)
      status_check(f.val(
        "call #{f.import("zeo_rt_ivar_get_dyn")}(#{borrow(self_operand)}, #{ptr}, #{len}, " \
        "#{f.iconst("i32", Capi::MAIN_BOX)}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    def ivar_write(node)
      store_ivar(ivar_key(node.name), lower_expr(node.value))
    end

    def store_ivar(name, value)
      at = borrow(value)
      ptr, len = rodata_ref(name)
      status_check(f.val(
        "call #{f.import("zeo_rt_ivar_set_dyn")}(#{borrow(self_operand)}, #{ptr}, #{len}, " \
        "#{f.iconst("i32", Capi::MAIN_BOX)}, #{at})",
      ))
      Operand.new(value.at, false, value.immediate)
    end

    # A bare `Foo` walks the cref chain, which at the top level is Object
    # alone. A miss is ruby's NameError, naming the qualified spelling.
    def constant_read(node)
      constant_named(node.name.to_s)
    end

    # `Outer::Inner = value`. The scope has to be a class this program
    # declares, because the runtime takes the owner as an id and only a
    # compiled class has one ze0 can name.
    def constant_path_write(node)
      scope = node.target.parent
      unless scope.is_a?(Prism::ConstantReadNode) && (found = resolve_class(cref, scope.name.to_s))
        raise Unsupported.new(node, "a constant assigned into a scope this program does not define")
      end

      value = lower_expr(node.value)
      at = borrow(value)
      nptr, nlen = rodata_ref(node.target.name.to_s)
      fptr, flen = rodata_ref(@file)
      f.ins "call #{f.import("zeo_rt_const_set_at")}(#{class_id(found)}, #{nptr}, #{nlen}, " \
            "#{at}, #{fptr}, #{flen}, #{f.iconst("i32", node.location.start_line)}, " \
            "#{f.iconst("i32", Capi::MAIN_BOX)})"
      Operand.new(value.at, false, value.immediate)
    end

    # The `/n`, `/e`, `/s` and `/u` suffixes; without one a regexp takes
    # the source's encoding.
    def regexp_encoding(node)
      return Capi::REGEXP_ENCODINGS[:none] if node.ascii_8bit?
      return Capi::REGEXP_ENCODINGS[:euc_jp] if node.euc_jp?
      return Capi::REGEXP_ENCODINGS[:windows_31j] if node.windows_31j?
      return Capi::REGEXP_ENCODINGS[:utf_8] if node.utf_8?

      Capi::REGEXP_ENCODINGS[:source]
    end

    # An interpolated regexp is compiled every time it is evaluated,
    # because its pattern is not known until then. A pattern the engine
    # rejects raises RegexpError at that point, where ruby's does.
    def interpolated_regexp(node)
      pattern = borrow(interpolated_string(node))
      slot = f.slot
      flag = ->(on) { f.iconst("i8", on ? 1 : 0) }
      status_check(f.val(
        "call #{f.import("zeo_rt_regexp_interp")}(#{pattern}, " \
        "#{flag.call(node.ignore_case?)}, #{flag.call(node.extended?)}, " \
        "#{flag.call(node.multi_line?)}, #{f.iconst("i8", regexp_encoding(node))}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # `__ENCODING__` names the script's own encoding. ze0 reads every
    # source it compiles as UTF-8, so that is the constant it answers.
    def source_encoding
      nptr, nlen = rodata_ref("UTF_8")
      qptr, qlen = rodata_ref("Encoding::UTF_8")
      slot = f.slot
      status_check(f.val(
        "call #{f.import("zeo_rt_const_get_on_value")}(#{borrow(anchored_constant("Encoding"))}, " \
        "#{nptr}, #{nlen}, #{qptr}, #{qlen}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # `:"a#{b}"` is that string, interned. Its name is not known until it
    # runs, so there is nothing a symbol literal could do here.
    def interpolated_symbol(node)
      slot = f.slot
      dynamic_send(borrow(interpolated_string(node)), :to_sym, [], addr_of(slot))
      Operand.new(slot, true, false)
    end

    # A non-interpolated regexp is one frozen object per site, which the
    # runtime keeps and every evaluation of the literal answers.
    def literal_regexp(node)
      slot = f.slot
      ptr, len = rodata_ref(node.unescaped)
      flag = ->(on) { f.iconst("i8", on ? 1 : 0) }
      status_check(f.val(
        "call #{f.import("zeo_rt_regexp_lit")}(#{f.iconst("i32", @program.regexp_site)}, #{ptr}, #{len}, " \
        "#{flag.call(node.ignore_case?)}, #{flag.call(node.extended?)}, #{flag.call(node.multi_line?)}, " \
        "#{f.iconst("i8", regexp_encoding(node))}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # A bare name searches the cref chain, which inside a class or one of
    # its methods is that class and then Object -- and a miss names the
    # qualified spelling, as ruby's NameError does.
    def anchored_constant(name)
      constant_named(name, name, [f.iconst("i32", Capi::OBJECT_CLASS)])
    end

    def constant_named(name, qualified = nil, chain = nil)
      qualified ||= owner == Names::OBJECT ? name : "#{owner}::#{name}"
      ids, n_ids = cid_array(chain || cref_ids)
      nptr, nlen = rodata_ref(name)
      qptr, qlen = rodata_ref(qualified)
      slot = f.slot
      status_check(f.val(
        "call #{f.import("zeo_rt_const_get_cref")}(#{ids}, #{n_ids}, #{nptr}, #{nlen}, #{qptr}, #{qlen}, " \
        "#{f.iconst("i8", 0)}, #{f.iconst("i32", Capi::MAIN_BOX)}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # `A::B`: the scope is lowered as an expression and the leaf read off
    # the value, so a scope ze0 cannot name at compile time still works.
    def constant_path_read(node)
      # `::Foo` is ANCHORED: the leading `::` means the top level, not an
      # empty namespace, so Object's own table is the whole search.
      return anchored_constant(node.name.to_s) if node.parent.nil?

      owner = static_scope(node.parent)
      name = node.name.to_s
      # The guard needs the owner's ID, so a scope ze0 cannot name is
      # refused -- but only for a name some body marks private. Every
      # other read is unguarded because nothing could guard it.
      if owner.nil? && @private_constants.key?(name)
        raise Unsupported.new(node, "a private constant read through a scope this program cannot name")
      end

      scope = lower_expr(node.parent)
      nptr, nlen = rodata_ref(name)
      qptr, qlen = rodata_ref(node.slice)
      private_constant_guard(owner, name, node.slice) if owner
      slot = f.slot
      status_check(f.val(
        "call #{f.import("zeo_rt_const_get_on_value")}(#{borrow(scope)}, #{nptr}, #{nlen}, " \
        "#{qptr}, #{qlen}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # The class a constant path's scope names, when this program declares
    # it. Only then can the read ask whether the constant is private:
    # `zeo_rt_const_private` takes the owner's ID.
    def static_scope(node)
      case node
      when Prism::ConstantReadNode then resolve_class(cref, node.name.to_s)
      when Prism::ConstantPathNode then node.parent && qualify_path(node)
      end
    end

    def qualify_path(node)
      up = static_scope(node.parent)
      up && @classes.key?("#{up}::#{node.name}") ? "#{up}::#{node.name}" : nil
    end

    # `A::B` where B is private raises, and the check is at the READ, not
    # in the lookup -- privacy is positional, so which directive last ran
    # is the run time's answer.
    def private_constant_guard(scope_name, name, path)
      return unless @classes.fetch(scope_name)[:private_constants].include?(name)

      nptr, nlen = rodata_ref(name)
      pptr, plen = rodata_ref(path)
      cid = class_id(scope_name)
      hidden, go = f.label, f.label
      f.ins "brif #{f.val("call #{f.import("zeo_rt_const_private")}(#{cid}, #{nptr}, #{nlen})")}, #{hidden}, #{go}"
      f.switch(hidden)
      status_check(f.val(
        "call #{f.import("zeo_rt_raise_private_constant")}(#{cid}, #{nptr}, #{nlen}, #{pptr}, #{plen})",
      ))
      f.ins "jump #{go}"
      f.switch(go)
    end

    # The table clones the value and stamps the location
    # `Module#const_source_location` reads back.
    def constant_write(node)
      store_constant(node.name.to_s, node, lower_expr(node.value))
    end

    def store_constant(name, node, value)
      at = borrow(value)
      nptr, nlen = rodata_ref(name)
      fptr, flen = rodata_ref(@file)
      f.ins "call #{f.import("zeo_rt_const_set_at")}(#{cref_ids.first}, #{nptr}, #{nlen}, " \
            "#{at}, #{fptr}, #{flen}, #{f.iconst("i32", node.location.start_line)}, " \
            "#{f.iconst("i32", Capi::MAIN_BOX)})"
      Operand.new(value.at, false, value.immediate)
    end

    # The cref a bare constant reads through: every enclosing scope,
    # innermost first, and `Object` last.
    def cref_ids
      cref_path.map { |name| class_id(name) } + [f.iconst("i32", Capi::OBJECT_CLASS)]
    end

    def cref_path = cref

    # A class's id, read out of `zeo_class_ids`. Ids are assigned when the
    # program is linked, so this is the one place ze0 learns one -- the
    # same indirection `zeo_syms` gives an interned symbol.
    def class_id(name)
      base = f.val("symbol_value.i64 #{f.symbol("zeo_class_ids")}")
      at = @program.class_slot(name) * 4
      f.val("load.i32 notrap aligned #{base}#{at.zero? ? "" : "+#{at}"}")
    end

    # A class-id array in a stack slot. The runtime reads it as `*const
    # u32`, and rodata has no alignment to give it.
    def cid_array(ids)
      slot = f.slot([ids.size * 4, Capi::SLOT_BYTES].max)
      ids.each_with_index do |id, i|
        at = i.zero? ? addr_of(slot) : f.stack_addr("#{slot}+#{i * 4}")
        f.ins "store notrap aligned #{id}, #{at}"
      end
      [addr_of(slot), f.iconst("i64", ids.size)]
    end

    # ---- locals ----

    # A fresh local, nil until something writes it. A name a block
    # captures gets a heap cell instead of the slot's own bytes, because
    # the closure outlives this frame and both must see one binding.
    def declare_local(name, boxed: false)
      slot = f.slot
      store_nil(addr_of(slot))
      unless boxed
        return locals[name] = Local.new(slot, nil)
      end

      cell = f.val("call #{f.import("zeo_rt_cell_new")}(#{f.iconst("i64", 0)})")
      f.ins "store notrap aligned #{cell}, #{addr_of(slot)}"
      locals[name] = Local.new(slot, :owned)
    end

    # A cell one of this block's `ProcEnv` rows names. The proc owns it, so
    # this scope only borrows.
    def declare_captured(name, env, index)
      cells = f.val("load.i64 notrap aligned #{env}")
      at = index.zero? ? cells : f.val("iadd.i64 #{cells}, #{f.iconst("i64", index * 8)}")
      slot = f.slot
      f.ins "store notrap aligned #{f.val("load.i64 notrap aligned #{at}")}, #{addr_of(slot)}"
      locals[name] = Local.new(slot, :borrowed)
    end

    # The cell a boxed local's slot points at.
    def cell_of(local)
      f.val("load.i64 notrap aligned #{addr_of(local.slot)}")
    end

    def local_read(node)
      read_local(local(node))
    end

    def read_local(local)
      return Operand.new(local.slot, false, false) unless local.boxed?

      slot = f.slot
      f.ins "call #{f.import("zeo_rt_cell_load")}(#{cell_of(local)}, #{addr_of(slot)})"
      Operand.new(slot, true, false)
    end

    def local_write(node)
      store_local(local(node), lower_expr(node.value))
    end

    # The old value goes after the new one is held, so `x = x` keeps it.
    def store_local(local, value)
      unless local.boxed?
        from = hand_over(value)
        release_if_heap(addr_of(local.slot))
        copy(from, addr_of(local.slot))
        return Operand.new(local.slot, false, false)
      end

      # The cell TAKES the value, so the assignment's own answer is the
      # pooled copy rather than the slot the cell now owns.
      at = borrow(value)
      retain_if_heap(at)
      f.ins "call #{f.import("zeo_rt_cell_store")}(#{cell_of(local)}, #{at})"
      Operand.new(value.at, false, value.immediate)
    end

    # A parameter's value into its local: the caller keeps its own
    # reference, so the copy retains first.
    def initialize_local(local, from)
      retain_if_heap(from)
      if local.boxed?
        f.ins "call #{f.import("zeo_rt_cell_store")}(#{cell_of(local)}, #{from})"
      else
        copy(from, addr_of(local.slot))
      end
    end

    def release_local(local)
      return release_if_heap(addr_of(local.slot)) unless local.boxed?
      return unless local.owns_cell?

      f.ins "call #{f.import("zeo_rt_cell_release")}(#{cell_of(local)})"
    end

    def local(node)
      locals.fetch(node.name) { raise Unsupported.new(node, "the local #{node.name} has no slot") }
    end

    # ---- multiple assignment ----

    # `a, b = 1, 2` and `a, *rest = list`. The runtime does the split --
    # an Array destructures directly and anything else goes through
    # ruby's `to_ary` rule -- and writes one owned value per target slot.
    def multi_write(node)
      value = lower_expr(node.value)
      split_into(node, borrow(value))
      # The assignment answers its right-hand side, which the split only
      # read.
      Operand.new(value.at, false, value.immediate)
    end

    # `zeo_rt_multi_split` over the value at `from`, writing one owned
    # value per target slot. `take` says the caller's reference passes to
    # the split, which a nested target's slot does and a local does not.
    def split_into(node, from, take: false)
      splat = rest_target(node.rest)
      targets = node.lefts + (splat ? [splat] : []) + node.rights
      slots = f.slot(Capi::SLOT_BYTES * targets.size)
      at = addr_of(slots)
      status_check(f.val(
        "call #{f.import("zeo_rt_multi_split")}(#{from}, #{f.iconst("i64", node.lefts.size)}, " \
        "#{f.iconst("i8", splat ? 1 : 0)}, #{f.iconst("i64", node.rights.size)}, #{at})",
      ))
      f.ins "call #{f.import("zeo_rt_release")}(#{from})" if take
      targets.each_with_index do |target, i|
        assign_target(target, i.zero? ? at : f.stack_addr("#{slots}+#{i * Capi::SLOT_BYTES}"))
      end
    end

    # The names inside a `|(a, b)|` parameter, written from the slot the
    # binder filled. The local owns that value, so the split only borrows
    # it.
    def unpack_destructures(params)
      params.destructures.each_key do |name|
        split_into(params.destructures.fetch(name), borrow(read_local(locals.fetch(name))))
      end
    end

    # The rest of a multiple assignment, or nil. A trailing comma
    # (`x, = list`) is ruby's "and drop the rest", which is the shape with
    # no rest slot at all.
    def rest_target(node)
      return nil if node.nil? || node.is_a?(Prism::ImplicitRestNode)
      raise Unsupported.new(node, "a rest of that shape") unless node.is_a?(Prism::SplatNode)

      node
    end

    # One split slot into one target. The slot holds an OWNED value, so
    # the target takes it rather than retaining a copy.
    def assign_target(node, from)
      node = node.expression if node.is_a?(Prism::SplatNode)
      # `a, * = list` names nothing, so its slot is simply let go.
      return f.ins("call #{f.import("zeo_rt_release")}(#{from})") if node.nil?

      taken = Operand.new(from, true, false)
      case node
      # A `(a, b)` parameter's inner names are parameter nodes, not
      # targets, but they are written exactly as a local is.
      when Prism::LocalVariableTargetNode, Prism::RequiredParameterNode
        store_local(local(node), taken)
      when Prism::InstanceVariableTargetNode then store_ivar(ivar_key(node.name), taken)
      when Prism::GlobalVariableTargetNode then store_global(node.name.to_s, taken)
      when Prism::ConstantTargetNode then store_constant(node.name.to_s, node, taken)
      when Prism::CallTargetNode
        recv = lower_expr(node.receiver)
        dynamic_send(borrow(recv), node.name, [taken], addr_of(f.slot))
      when Prism::IndexTargetNode
        recv = lower_expr(node.receiver)
        args = (node.arguments&.arguments || []).map { |a| lower_expr(a) }
        dynamic_send(borrow(recv), :[]=, args + [taken], addr_of(f.slot))
      when Prism::MultiTargetNode then multi_target(node, from)
      else raise Unsupported.new(node, "an assignment target of that shape")
      end
    end

    # `(a, b), c = pair, x`: the slot's own value splits again.
    def multi_target(node, from) = split_into(node, from, take: true)

    # ---- calls ----

    # The `Module` methods a class body calls to change what the class IS.
    # ze0 registers a class statically, so each of these would answer
    # differently from ruby rather than not at all: `attr_reader :x` left
    # `x` undefined, and `private` left a method public.
    CLASS_MACROS = %i[
      refine using
    ].freeze

    # The class-body macros the declaration pass has already answered.
    # Nothing is dispatched here: what is left is the VALUE ruby gives the
    # statement, and, for a positional `private :x`, the retag itself --
    # which is a run-time call because a reopen can change it.
    def lower_class_macro(node)
      args = node.arguments&.arguments || []
      name = node.name.to_s
      declared = @declared_macros[node.object_id]
      if name == "private_constant"
        raise Unsupported.new(node, "`#{name}` outside the class body's statements") unless declared

        # The class row carries the names; nothing runs here.
        accessor_names(node, args)
        return Operand.new(self_operand.at, false, self_operand.immediate)
      end
      if name == MODULE_FUNCTION
        raise Unsupported.new(node, "`#{name}` outside the class body's statements") unless declared
        return literal_nil if args.empty?

        return symbol_answer(accessor_names(node, args))
      end
      if VISIBILITY.include?(name)
        return literal_nil if args.empty?
        # `private def x` answers the `def`'s own value, and the row the
        # declaration pass wrote already carries the visibility.
        return args.map { |a| lower_expr(a) }.last if args.all?(Prism::DefNode)

        names = accessor_names(node, args)
        verb = f.iconst("i8", Capi::VISIBILITY_VERBS.fetch(name))
        cid = class_id(owner)
        names.each do |n|
          status_check(f.val(
            "call #{f.import("zeo_rt_runtime_set_visibility")}(#{cid}, #{sym_id(n)}, #{verb})",
          ))
        end
        return symbol_answer(names)
      end

      return lower_alias(node, args[0], args[1]) if name == "alias_method" && args.size == 2

      kind = ACCESSORS[node.name]
      # One the declaration pass did not reach -- written inside another
      # expression, or under a guard -- is an ordinary send of
      # `Module#attr_reader`, which mints the methods where it runs.
      return nil unless kind && declared

      defined = accessor_names(node, args).flat_map do |n|
        (kind == :writer ? [] : [n]) + (kind == :reader ? [] : ["#{n}="])
      end
      symbol_array(defined)
    end

    # `alias b a` and `alias_method :b, :a` are the same thing at run
    # time: the definee is `self` where `self` is a class or a module,
    # and the enclosing class otherwise -- `Object` at the top level.
    # The runtime resolves the source, so an alias of a builtin method
    # works exactly as it does for one the program wrote.
    def lower_alias(node, new_name, old_name)
      slot = f.slot
      status_check(f.val(
        "call #{f.import("zeo_rt_alias_in_default_definee")}(#{borrow(cref_value)}, " \
        "#{borrow(self_operand)}, #{borrow(alias_name(new_name))}, " \
        "#{borrow(alias_name(old_name))}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # The `alias` KEYWORD answers nil, where `alias_method` answers the
    # new name.
    def lower_alias_statement(node)
      discard(lower_alias(node, node.new_name, node.old_name))
      literal_nil
    end

    # `alias $new $old` aliases the STORAGE, so a write through either
    # name is visible through both.
    def lower_global_alias(node)
      new_ptr, new_len = rodata_ref(global_alias_name(node.new_name))
      old_ptr, old_len = rodata_ref(global_alias_name(node.old_name))
      f.ins "call #{f.import("zeo_rt_gvar_alias")}(#{f.iconst("i32", Capi::MAIN_BOX)}, " \
            "#{new_ptr}, #{new_len}, #{old_ptr}, #{old_len})"
      literal_nil
    end

    def global_alias_name(node)
      return node.name.to_s if node.is_a?(Prism::GlobalVariableReadNode)

      raise Unsupported.new(node, "an alias name of that shape")
    end

    def alias_name(node)
      raise Unsupported.new(node, "an alias name of that shape") unless NAME_LITERALS.any? { |k| node.is_a?(k) }

      literal_symbol(node.unescaped)
    end

    # A `require` the roots did not carry: a feature the runtime already
    # holds. The gated builtin's classes are registered concealed by the
    # backend, and this is what opens the gate and reveals them -- at the
    # require's own position, which is where ruby makes the constant
    # exist. The answer is folded here, as ruby's is: true the first time
    # the feature is named, false after.
    def lower_require(node)
      require_feature(node.arguments.arguments[0].unescaped)
    end

    # One feature's gate, opened where the statement stands. The answer is
    # ruby's: true the first time the program names it, false after.
    def require_feature(name)
      feature = canonical_feature(name)
      @program.add_feature(feature)
      eptr, elen = rodata_ref(feature)
      f.ins "call #{f.import("zeo_rt_feature_loaded")}(#{f.iconst("i32", Capi::MAIN_BOX)}, " \
            "#{eptr}, #{elen}, #{eptr}, #{elen})"
      first = !@required.key?(feature)
      @required[feature] = true
      literal_bool(first ? 1 : 0)
    end

    # `require "prism.so"` and `require "prism"` name one feature.
    def canonical_feature(name)
      name.sub(/\.(so|bundle|rb)\z/, "")
    end

    # What `private`, `module_function` and their kin answer: one name is
    # the Symbol itself, and several are an Array of them.
    def symbol_answer(names)
      names.size == 1 ? literal_symbol(names.first) : symbol_array(names)
    end

    def symbol_array(names)
      slot = f.slot
      at = addr_of(slot)
      f.ins "call #{f.import("zeo_rt_array_new")}(#{f.iconst("i64", names.size)}, #{at})"
      f.ins "call #{f.import("zeo_rt_pool_push")}(#{at})"
      names.each { |n| f.ins "call #{f.import("zeo_rt_array_push")}(#{at}, #{hand_over(literal_symbol(n))})" }
      Operand.new(slot, false, false)
    end

    # The verbs that run a STRING of ruby. The string form needs the
    # run-time compiler, which the sidecar asks the backend to link.
    EVAL_VERBS = %i[eval class_eval module_eval instance_eval].freeze

    def lower_call(node)
      @program.eval_install! if EVAL_VERBS.include?(node.name) && node.block.nil?
      if node.receiver.nil? && kind == :class_body
        raise Unsupported.new(node, "`#{node.name}` in a class body") if CLASS_MACROS.include?(node.name)

        macro = lower_class_macro(node)
        return macro if macro
      end
      # The splice consumed the file this names, so the declaration is
      # nothing but its own nil. A feature no load path carries is the
      # runtime's own, and this is where its gate opens.
      if autoload_call?(node)
        discard(require_feature(autoload_feature(node))) unless autoload_target(node)
        return literal_nil
      end
      # The splice consumes a `require` written as a top-level statement
      # and folds it to its own answer. Every other one -- guarded,
      # nested, or computed -- stays an ordinary send, and the run time
      # answers it from the units this program carries.
      if node.receiver.nil? && node.name == :require && !@deferred_call[node.object_id] && literal_feature?(node)
        return lower_require(node)
      end
      return safe_call(node) if safe_navigation?(node)

      # `dup`, because `pop` below would otherwise empty the prism node's
      # own array.
      args = node.arguments&.arguments&.dup || []
      # A trailing `k: v` list is its own channel, not a positional Hash.
      keywords = args.pop if args.last.is_a?(Prism::KeywordHashNode)
      args.each do |a|
        case a
        when Prism::KeywordHashNode, Prism::BlockArgumentNode
          raise Unsupported.new(a, "an argument of that shape")
        end
      end
      # A `*` splat or a `...` makes the count unknown here, so the send
      # hands the runtime an Array instead of a slot array.
      spread = args.any? { |a| a.is_a?(Prism::SplatNode) || a.is_a?(Prism::ForwardingArgumentsNode) }
      plain = node.block.nil? && keywords.nil? && !spread
      if plain && node.receiver.nil? && node.name == :block_given? && args.empty?
        block_given(node)
      elsif plain && node.receiver.nil? && (d = visible_def(node.name)) &&
            d[:params].plain? && d[:params].required.size == args.size
        direct_call(node, args, d)
      elsif plain && node.receiver.nil? && node.name == :puts
        kernel_puts(args)
      elsif plain && node.receiver && args.size == 1 && inline_binary?(node.name)
        binary(node.name, lower_expr(node.receiver), lower_expr(args[0]))
      else
        send_call(node, args, keywords)
      end
    end

    # The general send: a receiver, its positional arguments, an optional
    # keyword channel, and an optional block. The block is built LAST --
    # after the receiver, the arguments and the keywords -- because it is
    # MOVED in and nothing between its construction and the call may raise.
    def safe_navigation?(node) = node.call_operator_loc&.slice == "&."

    # `x&.y` answers nil without calling when `x` is nil -- NIL alone, not
    # anything falsy, so `false&.to_s` still answers "false".
    def safe_call(node)
      raise Unsupported.new(node, "a safe navigation write") if node.name.to_s.end_with?("=")

      recv = lower_expr(node.receiver)
      result = f.slot
      store_nil(addr_of(result))
      present = f.val("icmp ne #{tag_of(borrow(recv))}, #{f.iconst("i8", Capi::TAG_NIL)}")
      call, join = f.label, f.label
      f.ins "brif #{present}, #{call}, #{join}"
      f.switch(call)
      args = node.arguments&.arguments&.dup || []
      keywords = args.pop if args.last.is_a?(Prism::KeywordHashNode)
      move(send_call(node, args, keywords, recv), addr_of(result))
      f.ins "jump #{join}" unless f.terminated?
      f.switch(join)
      Operand.new(result, true, false)
    end

    def send_call(node, args, keywords, recv = nil)
      return vcall(node) if recv.nil? && node.variable_call?

      builder = block_builder(node, node.receiver.nil? && node.name == :lambda)
      # Ruby's `VM_CALL_FCALL`: a call the SOURCE wrote no receiver for
      # asks no visibility question at all.
      explicit = !node.receiver.nil?
      recv ||= node.receiver ? lower_expr(node.receiver) : self_operand
      result = f.slot
      if args.any? { |a| a.is_a?(Prism::SplatNode) || a.is_a?(Prism::ForwardingArgumentsNode) }
        splat_send(borrow(recv), node.name, args, addr_of(result),
                   keywords: keywords, builder: builder, explicit: explicit)
      elsif builder
        dynamic_send(borrow(recv), node.name, args.map { |a| lower_expr(a) }, addr_of(result),
                     breaks: true, keywords: keywords, explicit: explicit) { builder.call }
      else
        dynamic_send(borrow(recv), node.name, args.map { |a| lower_expr(a) }, addr_of(result),
                     keywords: keywords, explicit: explicit)
      end
      Operand.new(result, true, false)
    end

    # A send whose positional arguments include a `*` splat or a `...`.
    # The runtime reads ONE Array rather than a slot array, because only
    # it can spread a value whose length this compile does not know.
    #
    # `unmark` is ruby's rule that a splat-expanded Hash is positional
    # again, not a keyword channel.
    def splat_send(recv, name, args, into, keywords: nil, builder: nil, explicit: true)
      forwards = args.any?(Prism::ForwardingArgumentsNode)
      argv = new_array(args.size)
      args.each { |a| push_call_argument(argv, a) }
      kw = if keywords
             borrow(hash_literal(keywords))
           elsif forwards
             borrow(read_local(locals.fetch(:**)))
           else
             f.iconst("i64", 0)
           end
      blk = if builder
              builder.call
            elsif forwards
              block_arg_value(read_local(locals.fetch(:&)))
            else
              f.iconst("i64", 0)
            end
      status = f.val(
        if barrier?(explicit)
          "call #{f.import("zeo_rt_send_value_explicit_args_in")}(#{f.iconst("i32", 0)}, #{recv}, " \
            "#{sym_id(name)}, #{argv}, #{f.iconst("i8", 1)}, #{kw}, #{blk}, " \
            "#{running_caller}, #{into})"
        else
          "call #{f.import("zeo_rt_send_value_args_cached")}(#{callsite_ptr(explicit)}, " \
            "#{f.iconst("i32", 0)}, #{recv}, #{sym_id(name)}, #{argv}, #{f.iconst("i8", 1)}, " \
            "#{kw}, #{blk}, #{into})"
        end,
      )
      builder ? catch_break(status, into) : status_check(status)
    end

    # How this call's block gets made, or nil when it has none. The
    # function a literal block compiles to is emitted here; only its
    # `Proc` waits for the call.
    # `lambda { }` answers the block it is handed with the lambda bit set,
    # and the bit is not something `Kernel#lambda` can add later: the arity
    # and the strict binding are baked in at creation. Only a plain call
    # can be that `lambda`; a `super` never is.
    def block_builder(node, lambda_shape = false)
      case node.block
      when nil then nil
      when Prism::BlockNode
        body, captures = lower_block(node.block, lambda_shape)
        -> { proc_new(body, captures, node.block, lambda_shape) }
      when Prism::BlockArgumentNode
        # A bare `&` forwards the anonymous parameter, which binds the
        # same `&` slot a `...` does.
        expression = node.block.expression
        return -> { block_arg_value(read_local(locals.fetch(:&))) } if expression.nil?

        -> { block_arg_proc(expression) }
      else raise Unsupported.new(node.block, "a block of that shape")
      end
    end

    # The `Proc` the send is handed. Everything a shaped construction would
    # read from a `zeo_proc_shapes` row goes inline instead: `zeo backend`
    # defines that table with no rows, so the shaped entry is unreachable.
    def proc_new(body, captures, node, lambda_shape)
      shape = block_params(node)
      fn = f.callee(body, ["i64"] * 6, "i32")
      address = f.val("func_addr.i64 #{fn}")
      file, file_len = rodata_ref(@file)
      params, n_params = param_rows(shape)
      cells, n_cells = cell_array(captures)
      slot = f.slot
      null = f.iconst("i64", 0)
      lexical = yield_block || f.iconst("i64", 0)
      f.ins "call #{f.import("zeo_rt_proc_new")}(#{address}, #{cells}, #{n_cells}, " \
            "#{borrow(self_operand)}, #{lexical}, #{null}, " \
            "#{f.iconst("i32", proc_arity(shape, lambda_shape))}, " \
            "#{f.iconst("i32", proc_flags(node, lambda_shape))}, " \
            "#{params}, #{n_params}, #{file}, #{file_len}, " \
            "#{f.iconst("i32", node.location.start_line)}, #{null}, #{null}, #{addr_of(slot)})"
      addr_of(slot)
    end

    # A lambda catches its own `return`; every other proc that writes one
    # holds the activation it unwinds to.
    def proc_flags(node, lambda_shape)
      return Capi::PROC_LAMBDA if lambda_shape

      block_returns?(node.body) ? Capi::PROC_HOME : 0
    end

    # `Proc#arity`, mirroring `clif/params.rs`'s. A block's arity is
    # NEGATIVE only when a rest can swallow more; a lambda's is negative
    # whenever what it accepts is not exactly what it requires.
    def proc_arity(shape, lambda_shape)
      required = shape.required.size + shape.post.size
      required += 1 if shape.keywords.any?(&:required)
      most = shape.rest.nil? &&
             shape.required.size + shape.optional.size + shape.post.size +
             (shape.keywords.any? || shape.kwrest ? 1 : 0)
      positive = most && (!lambda_shape || required == most)
      positive ? required : -required - 1
    end

    # The cells this block captures, as the `*const *mut Cell` array the
    # proc reads. The proc takes its own reference to each, so this scope
    # keeps releasing its own.
    def cell_array(captures)
      return [f.iconst("i64", 0), f.iconst("i64", 0)] if captures.empty?

      slot = f.slot(8 * captures.size)
      at = addr_of(slot)
      captures.each_with_index do |n, i|
        cell = cell_of(locals.fetch(n))
        off = i * 8
        f.ins "store notrap aligned #{cell}, #{at}#{off.zero? ? "" : "+#{off}"}"
      end
      [at, f.iconst("i64", captures.size)]
    end

    # The `ParamC` rows behind `Proc#parameters`, on the stack. The rows
    # themselves are read during the call, but the NAME bytes they point at
    # are kept, so those come from rodata rather than from a slot.
    PARAM_ROW_BYTES = 24

    def param_rows(shape)
      rows = shape.rows
      return [f.iconst("i64", 0), f.iconst("i64", 0)] if rows.empty?

      slot = f.slot(PARAM_ROW_BYTES * rows.size)
      at = addr_of(slot)
      rows.each_with_index do |row, i|
        kind, name = row
        off = i * PARAM_ROW_BYTES
        ptr, len = rodata_ref(name.to_s)
        # The runtime renders a non-lambda block's `req` as `opt`.
        f.ins "store notrap aligned #{f.iconst("i8", Capi::PARAM_KINDS.index(kind))}, " \
              "#{at}#{off.zero? ? "" : "+#{off}"}"
        f.ins "store notrap aligned #{ptr}, #{at}+#{off + 8}"
        f.ins "store notrap aligned #{len}, #{at}+#{off + 16}"
      end
      [at, f.iconst("i64", rows.size)]
    end

    # `->(x) { }`: a lambda with no send around it.
    def lower_lambda(node)
      body, captures = lower_block(node, true)
      slot = f.slot
      copy(proc_new(body, captures, node, true), addr_of(slot))
      Operand.new(slot, true, false)
    end

    # `&expr`: a Proc passes through, a Symbol becomes its proc, nil means
    # no block, and anything else answers `to_proc`. The send spells "no
    # block" as a null pointer, which is what the nil check is for.
    def block_arg_proc(node) = block_arg_value(lower_expr(node))

    def block_arg_value(value)
      slot = f.slot
      at = addr_of(slot)
      status_check(f.val("call #{f.import("zeo_rt_block_arg_to_proc")}(#{borrow(value)}, #{at})"))
      absent = f.val("icmp eq #{tag_of(at)}, #{f.iconst("i8", Capi::TAG_NIL)}")
      f.val("select #{absent}, #{f.iconst("i64", 0)}, #{at}")
    end

    # A call to a `def` this program carries, straight to its body. The
    # block, when there is one, is built LAST and moved in.
    def direct_call(node, args, definition)
      raise Unsupported.new(node.block, "a block for a def that does not use one") if node.block && !definition[:block]

      operands = args.map { |a| lower_expr(a) }
      result = f.slot
      n_params = args.size + (definition[:block] ? 3 : 2)
      body = f.callee(body_symbol_of(definition[:owner], node.name, false), ["i64"] * n_params, "i32")
      addrs = [borrow(self_operand)] + operands.map { |o| borrow(o) }
      addrs << (block_builder(node)&.call || f.iconst("i64", 0)) if definition[:block]
      status = f.val("call #{body}(#{(addrs + [addr_of(result)]).join(", ")})")
      node.block ? catch_break(status, addr_of(result)) : status_check(status)
      Operand.new(result, true, false)
    end

    def kernel_puts(args)
      argv = args_array(args.map { |a| lower_expr(a) })
      result = f.slot
      status_check(f.val("call #{f.import("zeo_rt_kernel_puts")}(#{argv}, #{f.iconst("i64", args.size)}, #{addr_of(result)})"))
      Operand.new(result, false, true)
    end

    # The cached dynamic send: `recv.name(*args)`. Not `send`: that would
    # replace `Object#send` on every Lower.
    def dynamic_send(recv, name, operands, into, breaks: false, keywords: nil, explicit: true)
      argv = args_array(operands)
      kw = keywords ? borrow(hash_literal(keywords)) : nil
      blk = block_given? ? yield : f.iconst("i64", 0)
      sym_id = sym_id(name)
      channels = kw ? "#{kw}, #{blk}" : blk.to_s
      count = f.iconst("i64", operands.size)
      status = f.val(
        if barrier?(explicit)
          entry = kw ? "zeo_rt_send_value_explicit_kw_in" : "zeo_rt_send_value_explicit_in"
          "call #{f.import(entry)}(#{f.iconst("i32", 0)}, #{recv}, #{sym_id}, " \
            "#{argv}, #{count}, #{channels}, #{running_caller}, #{into})"
        else
          entry = kw ? "zeo_rt_send_value_kw_cached" : "zeo_rt_send_value_cached"
          "call #{f.import(entry)}(#{callsite_ptr(explicit)}, #{f.iconst("i32", 0)}, #{recv}, " \
            "#{sym_id}, #{argv}, #{count}, #{channels}, #{into})"
        end,
      )
      breaks ? catch_break(status, into) : status_check(status)
    end

    # Whether this send has to ask the RUN TIME for its caller class. A
    # body the runtime installs has no lexical class to name -- the one
    # the source wrote it in is not the one it lands on -- so the site
    # cannot record the answer and cannot be cached either.
    def barrier?(explicit) = explicit && scope.dynamic_caller

    # `self`'s class, which is that answer.
    def running_caller
      f.val("call #{f.import("zeo_rt_class_of")}(#{borrow(self_operand)})")
    end

    # A bare name with no arguments, no parentheses and no receiver is
    # ruby's VCALL. It dispatches exactly as a call to `self` does; only
    # the MISS differs, and it is `NameError: undefined local variable or
    # method`, never `NoMethodError`.
    def vcall(node)
      result = f.slot
      status = f.val(
        "call #{f.import("zeo_rt_send_value_vcall_cached")}(#{callsite_ptr(false)}, " \
        "#{f.iconst("i32", 0)}, #{borrow(self_operand)}, #{sym_id(node.name)}, " \
        "#{addr_of(result)})",
      )
      status_check(status)
      Operand.new(result, true, false)
    end

    # The program's next inline-cache slot, as a pointer. The slot
    # records the class the site is written in: a filled site was vetted
    # when it filled, so the hot path never reads it back.
    def callsite_ptr(explicit)
      site = f.val("symbol_value.i64 #{f.symbol("zeo_callsites")}")
      offset = @program.callsite(explicit ? scope.caller_class : "") * Capi::CALLSITE_BYTES
      return site if offset.zero?

      f.val("iadd.i64 #{site}, #{f.iconst("i64", offset)}")
    end

    # A send that passed a block lands here: a `Break` signal's value IS
    # the send's value, and every other signal is a real unwind.
    def catch_break(status, into)
      ok, signalled, take = f.label, f.label, f.label
      f.ins "brif #{status}, #{signalled}, #{ok}"
      f.switch(signalled)
      kind = f.val("call #{f.import("zeo_rt_signal_kind")}()")
      f.ins "brif #{f.val("icmp eq #{kind}, #{f.iconst("i8", Capi::SIGNAL_BREAK)}")}, #{take}, #{raise_block}"
      f.switch(take)
      f.val("call #{f.import("zeo_rt_signal_take")}(#{into})")
      f.ins "jump #{ok}"
      f.switch(ok)
    end

    # The arguments of a call, contiguous: one slot of `n` values, each
    # a borrowed copy. A null pointer when there are none.
    def args_array(operands)
      return f.iconst("i64", 0) if operands.empty?

      slot = f.slot(Capi::SLOT_BYTES * operands.size)
      operands.each_with_index do |o, i|
        from = borrow(o)
        to = i.zero? ? addr_of(slot) : f.stack_addr("#{slot}+#{i * Capi::SLOT_BYTES}")
        copy(from, to)
      end
      addr_of(slot)
    end

    def inline_binary?(name)
      INT_ARITH.key?(name) || INT_COMPARE.key?(name)
    end

    # `a OP b` with the Int/Int fast path inline and the send otherwise.
    def binary(name, lhs, rhs)
      la = borrow(lhs)
      ra = borrow(rhs)
      result = f.slot
      out_at = addr_of(result)
      int = f.iconst("i8", Capi::TAG_INT)
      both = f.val("band #{f.val("icmp eq #{tag_of(la)}, #{int}")}, #{f.val("icmp eq #{tag_of(ra)}, #{int}")}")
      fast, slow, join = f.label, f.label, f.label
      f.ins "brif #{both}, #{fast}, #{slow}"
      f.switch(fast)
      a = f.val("load.i64 notrap aligned #{la}+8")
      b = f.val("load.i64 notrap aligned #{ra}+8")
      if (arith = INT_ARITH[name])
        value, overflowed = f.vals("#{arith[0]} #{a}, #{b}")
        big, small = f.label, f.label
        f.ins "brif #{overflowed}, #{big}, #{small}"
        f.switch(small)
        f.ins "store notrap aligned #{int}, #{out_at}"
        f.ins "store notrap aligned #{value}, #{out_at}+8"
        f.ins "jump #{join}"
        f.switch(big)
        f.ins "call #{f.import(arith[1])}(#{la}, #{ra}, #{out_at})"
        f.ins "jump #{join}"
      else
        answer = f.val("icmp #{INT_COMPARE[name]} #{a}, #{b}")
        f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_BOOL)}, #{out_at}"
        f.ins "store notrap aligned #{answer}, #{out_at}+8"
        f.ins "jump #{join}"
      end
      f.switch(slow)
      dynamic_send(la, name, [Operand.new(rhs.at, false, rhs.immediate)], out_at)
      f.ins "jump #{join}"
      f.switch(join)
      Operand.new(result, true, false)
    end

    # ---- control flow ----

    # `if` and `unless`. A guard this compile can decide leaves only the
    # branch that runs, so the other is never lowered -- which is what
    # lets a program hold one written for another engine entirely.
    def lower_conditional(node)
      negate = node.is_a?(Prism::UnlessNode)
      otherwise = negate ? node.else_clause : node.subsequent
      unless Guards.static_cond(node.predicate).nil?
        live = live_branch(node)
        return live ? lower_expr(live) : literal_nil
      end

      lower_if(node.predicate, node.statements, otherwise, negate)
    end

    # The branch a decided guard runs, or nil when it runs neither. An
    # `elsif` comes back as the `if` it is, decided in its own turn.
    def live_branch(node)
      decided = Guards.static_cond(node.predicate)
      return nil if decided.nil?

      negate = node.is_a?(Prism::UnlessNode)
      return node.statements if negate ? !decided : decided

      negate ? node.else_clause : node.subsequent
    end

    # A branch's statements, whichever shape it came in as: a bare run, an
    # `else`, or the `if` an `elsif` is.
    def branch_statements(node)
      case node
      when nil then []
      when Prism::StatementsNode then node.body
      when Prism::ElseNode then node.statements&.body || []
      else [node]
      end
    end

    def lower_if(predicate, statements, otherwise, negate)
      truth = truthy(lower_expr(predicate))
      yes, no, join = f.label, f.label, f.label
      result = f.slot
      f.ins "brif #{truth}, #{negate ? no : yes}, #{negate ? yes : no}"
      f.switch(yes)
      arm(lower_statements(statements), result, join)
      f.switch(no)
      arm(otherwise ? lower_expr(otherwise) : literal_nil, result, join)
      f.switch(join)
      Operand.new(result, true, false)
    end

    # One arm's value into the shared result slot, unless the arm left
    # through a `return`.
    def arm(value, result, join)
      return if f.terminated?

      move(value, addr_of(result))
      f.ins "jump #{join}"
    end

    # A loop answers nil unless a `break` gives it a value, so the result
    # slot is seeded before the head and only a `break` writes it.
    def lower_while(predicate, statements, negate)
      mark = f.val("call #{f.import("zeo_rt_pool_mark")}()")
      head, body, done = f.label, f.label, f.label
      result = f.slot
      store_nil(addr_of(result))
      f.ins "jump #{head}"
      f.switch(head)
      status_check(f.val("call #{f.import("zeo_rt_check_ints")}()"))
      truth = truthy(lower_expr(predicate))
      f.ins "brif #{truth}, #{negate ? done : body}, #{negate ? body : done}"
      f.switch(body)
      scope.loops.push(Loop.new(head, done, result, mark, scope.handling_depth, scope.ensure_depth, body))
      body_statements(statements).each do |s|
        set_line(s)
        discard(lower_expr(s))
        break if f.terminated?
      end
      scope.loops.pop
      unless f.terminated?
        f.ins "call #{f.import("zeo_rt_pool_reset")}(#{mark})"
        f.ins "jump #{head}"
      end
      f.switch(done)
      f.ins "call #{f.import("zeo_rt_pool_reset")}(#{mark})"
      Operand.new(result, true, false)
    end

    # `for x in coll` performs NO type dispatch: ruby compiles it to
    # `coll.each { |x| ... }`, and the runtime driver decides per
    # receiver -- a live Array indexes the receiver itself, an
    # Int-bounded Range counts, and everything else walks what `each`
    # yielded. The index is a name of the ENCLOSING scope rather than a
    # block parameter, so it outlives the loop.
    def lower_for(node)
      packed = node.index.is_a?(Prism::MultiTargetNode)
      state = f.stack_addr(f.slot(Capi::FOR_STATE_BYTES))
      status_check(f.val(
        "call #{f.import("zeo_rt_for_begin")}(#{borrow(lower_expr(node.collection))}, " \
        "#{f.iconst("i8", packed ? 1 : 0)}, #{state})",
      ))
      mark = f.val("call #{f.import("zeo_rt_pool_mark")}()")
      head, body, done = f.label, f.label, f.label
      walked, landing = f.label, f.label
      result = f.slot
      store_nil(addr_of(result))
      elem, more = f.slot, f.slot
      f.ins "jump #{head}"

      f.switch(head)
      f.ins "call #{f.import("zeo_rt_for_next")}(#{state}, #{addr_of(elem)}, #{addr_of(more)})"
      f.ins "brif #{f.val("load.i8 notrap aligned #{addr_of(more)}")}, #{body}, #{walked}"

      f.switch(body)
      packed ? split_into(node.index, addr_of(elem), take: true) : assign_target(node.index, addr_of(elem))
      # The state holds the collection, so a raise inside the body
      # releases it before the enclosing landing runs.
      outer = scope.raise_block
      scope.raise_block = landing
      status_check(f.val("call #{f.import("zeo_rt_check_ints")}()"))
      scope.loops.push(
        Loop.new(head, done, result, mark, scope.handling_depth, scope.ensure_depth, body),
      )
      body_statements(node.statements).each do |s|
        set_line(s)
        discard(lower_expr(s))
        break if f.terminated?
      end
      scope.loops.pop
      scope.raise_block = outer
      unless f.terminated?
        f.ins "call #{f.import("zeo_rt_pool_reset")}(#{mark})"
        f.ins "jump #{head}"
      end

      # Walked to the end: the loop answers the collection. A `break`
      # supplies its own and jumps straight to `done`.
      f.switch(walked)
      f.ins "call #{f.import("zeo_rt_for_result")}(#{state}, #{addr_of(result)})"
      f.ins "jump #{done}"

      f.switch(landing)
      f.ins "call #{f.import("zeo_rt_for_end")}(#{state})"
      f.ins "jump #{outer}"

      f.switch(done)
      f.ins "call #{f.import("zeo_rt_for_end")}(#{state})"
      f.ins "call #{f.import("zeo_rt_pool_reset")}(#{mark})"
      Operand.new(result, true, false)
    end

    # `a && b` and `a || b` answer one of their OPERANDS, not a boolean,
    # so the arm that runs moves its value into the shared slot.
    def and_or(left, right, conjunction)
      value = lower_expr(left)
      truth = truthy(value)
      result = f.slot
      short, other, join = f.label, f.label, f.label
      f.ins "brif #{truth}, #{conjunction ? other : short}, #{conjunction ? short : other}"
      f.switch(short)
      arm(value, result, join)
      f.switch(other)
      arm(lower_expr(right), result, join)
      f.switch(join)
      Operand.new(result, true, false)
    end

    # `case`: each `when` value is tested with `===` against the subject,
    # left to right, and the first hit's body answers. A subjectless
    # `case` tests each value's own truth, ruby's if-chain sugar.
    #
    # Every test runs before any body, so the chain of fall-through blocks
    # stays open until the `else` closes it and no block is left behind
    # without a terminator.
    def lower_case(node)
      subject = nil
      if node.predicate
        subject = lower_expr(node.predicate)
        borrow(subject)
      end
      result = f.slot
      # The `===` answer's scratch byte: a whole slot, of which byte 0 is
      # the only one written.
      hit_at = addr_of(f.slot)
      join = f.label
      bodies = node.conditions.map do |arm_node|
        body = f.label
        arm_node.conditions.each do |value_node|
          hit = case_test(subject, value_node, hit_at)
          fall = f.label
          f.ins "brif #{hit}, #{body}, #{fall}"
          f.switch(fall)
        end
        [body, arm_node.statements]
      end
      # Nothing hit: the `else`, or nil.
      arm(node.else_clause ? lower_statements(node.else_clause.statements) : literal_nil, result, join)
      bodies.each do |body, statements|
        f.switch(body)
        arm(lower_statements(statements), result, join)
      end
      f.switch(join)
      Operand.new(result, true, false)
    end

    def case_test(subject, node, hit_at)
      raise Unsupported.new(node, "a splat in a `when`") if node.is_a?(Prism::SplatNode)

      value = lower_expr(node)

      return truthy(value) unless subject

      at = borrow(value)
      status_check(f.val("call #{f.import("zeo_rt_case_eq")}(#{at}, #{addr_of(subject)}, #{hit_at})"))
      f.val("load.i8 notrap aligned #{hit_at}")
    end

    # `yield` calls the block the caller handed this method. A method with
    # no block raises ruby's LocalJumpError, which the runtime does.
    def lower_yield(node)
      blk = yield_block
      raise Unsupported.new(node, "a yield outside a method that takes a block") if blk.nil?

      args = (node.arguments&.arguments || []).dup
      return yield_of_args(node, blk, args) if spread_arguments?(args)

      argv = args_array(args.map { |a| lower_expr(a) })
      slot = f.slot
      status_check(f.val(
        "call #{f.import("zeo_rt_yield")}(#{blk}, #{argv}, #{f.iconst("i64", args.size)}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # `yield(*a)` and `yield 1, k: 2`: how many values reach the block is
    # a run-time fact, so the list is built as an Array and the keywords
    # as a Hash beside it, and the block binds from the contents.
    def yield_of_args(node, blk, args)
      keywords = args.pop if args.last.is_a?(Prism::KeywordHashNode)
      argv = new_array(args.size)
      args.each { |a| push_call_argument(argv, a) }
      kw = keywords ? borrow(hash_literal(keywords)) : f.iconst("i64", 0)
      slot = f.slot
      status_check(f.val(
        "call #{f.import("zeo_rt_yield_args")}(#{blk}, #{argv}, #{kw}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # Whether an argument list's length is only known at run time: a `*`
    # splat, a `...`, or a keyword tail that may be empty when it runs.
    def spread_arguments?(args)
      args.last.is_a?(Prism::KeywordHashNode) ||
        args.any? { |a| a.is_a?(Prism::SplatNode) || a.is_a?(Prism::ForwardingArgumentsNode) }
    end

    # ---- defined? ----
    #
    # `defined?(expr)` answers ruby's prose for what the expression IS, or
    # nil when it is not there. What is inside never runs for its value: a
    # method is asked about rather than called. The parts that ARE
    # evaluated -- a call's receiver, a constant's scope -- run under a
    # landing that swallows a raise and answers nil, which is what makes
    # `defined?(missing.thing)` safe to write.

    # The forms whose answer is settled without running anything.
    DEFINED_STATIC = {
      Prism::SelfNode => "self",
      Prism::NilNode => "nil",
      Prism::TrueNode => "true",
      Prism::FalseNode => "false",
      Prism::LocalVariableReadNode => "local-variable",
    }.freeze

    # Every literal and every control-flow form is an "expression"; ruby
    # asks nothing further about what is inside one.
    DEFINED_EXPRESSION = [
      Prism::IntegerNode, Prism::FloatNode, Prism::SymbolNode, Prism::StringNode,
      Prism::InterpolatedStringNode, Prism::InterpolatedSymbolNode, Prism::ArrayNode,
      Prism::HashNode, Prism::RangeNode, Prism::RegularExpressionNode, Prism::LambdaNode,
      Prism::AndNode, Prism::OrNode, Prism::DefinedNode, Prism::IfNode, Prism::UnlessNode,
      Prism::CaseNode, Prism::BeginNode, Prism::WhileNode, Prism::UntilNode,
      Prism::DefNode, Prism::ClassNode, Prism::ModuleNode,
      Prism::InterpolatedRegularExpressionNode, Prism::RationalNode, Prism::ImaginaryNode,
      Prism::SourceFileNode, Prism::SourceLineNode, Prism::SourceEncodingNode,
      Prism::ForNode,
    ].freeze

    def lower_defined(node) = defined_answer(node.value)

    # One of the `$1` family is defined where it holds a value: a group
    # the pattern never declared, and every one of them before the first
    # match, answers nil.
    def defined_match(value)
      present = f.val("icmp ne #{tag_of(borrow(value))}, #{f.iconst("i8", Capi::TAG_NIL)}")
      defined_if(present, "global-variable")
    end

    def defined_answer(inner)
      answer = DEFINED_STATIC[inner.class]
      answer ||= "expression" if DEFINED_EXPRESSION.include?(inner.class)
      # A write is an "assignment" whatever it writes to, and it does not
      # run. Prism names every one of them `...WriteNode`.
      answer ||= "assignment" if inner.class.name.end_with?("WriteNode")
      return literal_string(answer) if answer

      case inner
      when Prism::InstanceVariableReadNode
        hit = flag_slot
        ptr, len = rodata_ref(ivar_key(inner.name))
        status_check(f.val(
          "call #{f.import("zeo_rt_defined_ivar")}(#{borrow(self_operand)}, #{ptr}, #{len}, #{addr_of(hit)})",
        ))
        defined_if(flag_of(hit), "instance-variable")
      when Prism::GlobalVariableReadNode
        # `$~` always answers, even before the first match.
        return literal_string("global-variable") if inner.name == :$~

        ptr, len = rodata_ref(inner.name.to_s)
        defined_if(f.val(
          "call #{f.import("zeo_rt_defined_gvar")}(#{f.iconst("i32", Capi::MAIN_BOX)}, #{ptr}, #{len})",
        ), "global-variable")
      when Prism::NumberedReferenceReadNode
        defined_match(last_match(Capi::LAST_MATCH_GROUP, inner.number))
      when Prism::BackReferenceReadNode then defined_match(back_reference(inner))
      when Prism::ConstantReadNode, Prism::ConstantPathNode then defined_constant(inner)
      when Prism::CallNode then defined_call(inner)
      when Prism::YieldNode
        yield_block.nil? ? literal_nil : defined_if(block_present, "yield")
      else raise Unsupported.new(inner, "a `defined?` of that form")
      end
    end

    # The forms nothing can leave undefined, so a call taking one as an
    # argument answers on the method alone.
    DEFINED_ALWAYS = (DEFINED_STATIC.keys + [
      Prism::IntegerNode, Prism::FloatNode, Prism::SymbolNode, Prism::StringNode,
    ]).freeze

    # The cref walk is the only thing that knows where a bare constant
    # lives, so the read runs and a miss arrives as a swallowed raise.
    def defined_constant(node)
      hit = flag_slot
      swallowed do
        value = lower_expr(node)
        set_flag(hit)
        value
      end
      defined_if(flag_of(hit), "constant")
    end

    # `defined?(recv.name)` asks whether the method is there rather than
    # calling it. The receiver IS evaluated, under the swallowing landing.
    # A call with no receiver asks `self` and sees its private methods
    # too, which is the difference from `defined?(self.name)`.
    def defined_call(node)
      raise Unsupported.new(node, "a `defined?` of a call with a block") if node.block
      # `defined?(f(a))` is "method" only when the call resolves AND each
      # argument is itself defined. An argument whose answer is settled
      # here costs nothing; anything else is refused rather than guessed.
      (node.arguments&.arguments || []).each do |a|
        raise Unsupported.new(a, "a `defined?` argument of that shape") unless DEFINED_ALWAYS.include?(a.class)
      end

      hit = flag_slot
      swallowed do
        recv = node.receiver ? lower_expr(node.receiver) : self_operand
        all = f.iconst("i8", node.receiver ? 0 : 1)
        f.ins "call #{f.import("zeo_rt_defined_method")}(#{borrow(recv)}, #{sym_id(node.name)}, " \
              "#{all}, #{addr_of(hit)})"
        nil
      end
      defined_if(flag_of(hit), "method")
    end

    # `answer` when `hit` is set, nil when it is not. The String is built
    # only on the branch that answers it.
    def defined_if(hit, answer)
      slot = f.slot
      store_nil(addr_of(slot))
      taken, join = f.label, f.label
      f.ins "brif #{hit}, #{taken}, #{join}"
      f.switch(taken)
      move(literal_string(answer), addr_of(slot))
      f.ins "jump #{join}"
      f.switch(join)
      Operand.new(slot, true, false)
    end

    # A one-byte answer slot, false until something sets it.
    def flag_slot
      slot = f.slot(1)
      f.ins "store notrap aligned #{f.iconst("i8", 0)}, #{addr_of(slot)}"
      slot
    end

    def set_flag(slot)
      f.ins "store notrap aligned #{f.iconst("i8", 1)}, #{addr_of(slot)}"
    end

    def flag_of(slot) = f.val("load.i8 notrap aligned #{addr_of(slot)}")

    # Whether this scope was handed a block.
    def block_present
      f.val("icmp ne #{yield_block}, #{f.iconst("i64", 0)}")
    end

    # Run the block under a landing that eats a raise, so a part of the
    # expression that blows up leaves `defined?` answering nil rather than
    # unwinding out of it.
    def swallowed
      outer = scope.raise_block
      landing, join = f.label, f.label
      scope.raise_block = landing
      value = yield
      scope.raise_block = outer
      discard(value) if value
      f.ins "jump #{join}" unless f.terminated?
      f.switch(landing)
      # The payload is taken so the pool releases it and nothing
      # downstream sees a raise still armed.
      taken = f.slot
      f.val("call #{f.import("zeo_rt_signal_take")}(#{addr_of(taken)})")
      borrow(Operand.new(taken, true, false))
      f.ins "jump #{join}"
      f.switch(join)
    end

    # `begin ... end`. Without a clause it is a bare grouping and the
    # statements are the whole of it.
    #
    # With one, the body lowers against a landing of its own -- the one
    # piece of state a `begin` swaps -- and every fallible call inside it
    # arrives there. A Raise is taken and matched against the clauses;
    # every other signal is a real unwind and propagates untouched, which
    # is safe because `zeo_rt_signal_take` only consumes the payload of a
    # Raise, Break, Next or Return.
    def lower_begin(node)
      return lower_ensure(node) if node.ensure_clause
      return lower_statements(node.statements) if node.rescue_clause.nil?

      lower_rescued(node)
    end

    # `ensure` runs its clause on the way out however the body leaves: a
    # normal finish, a raise, or a jump the clause stands between.
    def lower_ensure(node)
      clause = node.ensure_clause
      outer = scope.raise_block
      landing, done = f.label, f.label
      result = f.slot
      store_nil(addr_of(result))
      jumps_before = scope.ensure_jumps

      scope.raise_block = landing
      scope.ensure_depth += 1
      value = node.rescue_clause ? lower_rescued(node) : lower_statements(node.statements)
      scope.ensure_depth -= 1
      scope.raise_block = outer
      unless f.terminated?
        move(value, addr_of(result))
        discard(lower_statements(clause.statements))
        f.ins "jump #{done}" unless f.terminated?
      end

      # The signal path. The signal is set aside so the clause runs on a
      # clear slot -- a raise of its own then WINS, as ruby's does -- and
      # `$!` names the exception being carried while it runs.
      f.switch(landing)
      saved = f.val("call #{f.import("zeo_rt_signal_save")}()")
      pushed = f.val("call #{f.import("zeo_rt_propagating_enter")}(#{saved})")
      raised = f.label
      scope.raise_block = raised
      scope.ensure_depth += 1
      discard(lower_statements(clause.statements))
      scope.ensure_depth -= 1
      scope.raise_block = outer
      # Only now is it known whether a jump really crossed this clause.
      # Without one, nothing here may claim a signal that is passing
      # through on its way to somebody else.
      target = settle_target if scope.ensure_jumps > jumps_before
      settle = f.label if target
      after = settle || outer
      unless f.terminated?
        f.ins "call #{f.import("zeo_rt_propagating_leave")}(#{pushed})"
        f.ins "call #{f.import("zeo_rt_signal_restore")}(#{saved})"
        f.ins "jump #{after}"
      end
      # A raise from the clause itself WINS, as ruby's does, so the one
      # being carried is dropped rather than put back.
      f.switch(raised)
      f.ins "call #{f.import("zeo_rt_propagating_leave")}(#{pushed})"
      f.ins "call #{f.import("zeo_rt_signal_drop")}(#{saved})"
      f.ins "jump #{after}"
      lower_settle(settle, outer, target) if settle
      f.switch(done)
      Operand.new(result, true, false)
    end

    # Where an ensure-crossing jump lands once the clause has run, and
    # what fills its value. A loop counts only at the SAME ensure depth:
    # a farther one has another clause in between, and THAT one settles
    # the jump. With no loop in reach a block's own boundary is the
    # target, where `next` is the block's value and `break` keeps
    # travelling -- it belongs to the call site, not to anything here.
    Settle = Struct.new(:brk, :nxt, :rdo, :mark, :handling)

    def settle_target
      if (loop = scope.loops.last)
        return nil unless loop.depth == scope.ensure_depth

        return Settle.new(
          [loop.done, addr_of(loop.result)], [loop.head, nil], loop.body, loop.mark, loop.handling,
        )
      end
      return nil unless kind == :block && scope.ensure_depth.zero?

      Settle.new(nil, [done_block, out], scope.redo_block, nil, 0)
    end

    # Turn the signal an ensure-crossing jump armed back into the jump it
    # was. Anything this target does not claim is a real unwind and
    # passes through untouched.
    def lower_settle(settle, outer, target)
      f.switch(settle)
      signal = f.val("call #{f.import("zeo_rt_signal_kind")}()")
      # `redo` carries nothing, so clearing its slot is a save and a drop.
      jumps = {
        Capi::SIGNAL_BREAK => target.brk,
        Capi::SIGNAL_NEXT => target.nxt,
        Capi::SIGNAL_REDO => (target.rdo ? [target.rdo, nil] : nil),
      }
      arms = jumps.filter_map do |kind, dest|
        next unless dest

        taken, rest = f.label, f.label
        is = f.val("icmp eq #{signal}, #{f.iconst("i8", kind)}")
        f.ins "brif #{is}, #{taken}, #{rest}"
        f.switch(rest)
        [taken, dest, kind]
      end
      f.ins "jump #{outer}"
      arms.each { |taken, (dest, at), kind| settle_arm(taken, dest, at, kind, target) }
    end

    # One arm of the settle: take the value the signal carries, put it
    # where the jump would have, and go. `redo` carries nothing, so
    # clearing its slot is a save and a drop rather than a take.
    def settle_arm(taken, dest, at, kind, target)
      f.switch(taken)
      if kind == Capi::SIGNAL_REDO
        saved = f.val("call #{f.import("zeo_rt_signal_save")}()")
        f.ins "call #{f.import("zeo_rt_signal_drop")}(#{saved})"
      else
        slot = f.slot
        f.val("call #{f.import("zeo_rt_signal_take")}(#{addr_of(slot)})")
        value = Operand.new(slot, true, false)
        at ? move(value, at) : discard(value)
      end
      pop_handling(target.handling)
      # An iteration that starts over releases what the last one made,
      # exactly as the end of a normal one does.
      f.ins "call #{f.import("zeo_rt_pool_reset")}(#{target.mark})" if target.mark && kind == Capi::SIGNAL_NEXT
      f.ins "jump #{dest}"
    end

    def lower_rescued(node)
      outer = scope.raise_block
      landing, done = f.label, f.label
      result = f.slot
      store_nil(addr_of(result))

      scope.raise_block = landing
      value = lower_statements(node.statements)
      # An `else` runs only when the body finished, and it runs OUTSIDE
      # the clauses: a raise there is not this begin's to catch.
      scope.raise_block = outer
      if node.else_clause && !f.terminated?
        discard(value)
        value = lower_statements(node.else_clause.statements)
      end
      unless f.terminated?
        move(value, addr_of(result))
        f.ins "jump #{done}"
      end

      f.switch(landing)
      lower_rescue_clauses(node.rescue_clause, outer, result, done)
      f.switch(done)
      Operand.new(result, true, false)
    end

    # The begin's landing: take the exception, try each clause in turn,
    # and re-arm the Raise when none matched.
    def lower_rescue_clauses(clause, outer, result, done)
      exc = take_raised(outer)
      while clause
        matched = clause_matches(clause, exc, outer)
        body, nxt = f.label, f.label
        f.ins "brif #{matched}, #{body}, #{nxt}"
        f.switch(body)
        lower_rescue_body(clause.reference, exc, outer, result, done) do
          lower_statements(clause.statements)
        end
        f.switch(nxt)
        clause = clause.subsequent
      end
      rearm_raise(exc, outer)
    end

    # The landing both `rescue` shapes share. Only a Raise is this
    # construct's; anything else on the signal is someone else's unwind
    # and leaves through `outer`. Taking it hands the POOL the reference,
    # so every use of the exception below borrows.
    def take_raised(outer)
      kind = f.val("call #{f.import("zeo_rt_signal_kind")}()")
      raised = f.val("icmp eq #{kind}, #{f.iconst("i8", Capi::SIGNAL_RAISE)}")
      take = f.label
      f.ins "brif #{raised}, #{take}, #{outer}"
      f.switch(take)
      exc = f.slot
      f.val("call #{f.import("zeo_rt_signal_take")}(#{addr_of(exc)})")
      borrow(Operand.new(exc, true, false))
      exc
    end

    # Nothing matched: the pool keeps its own reference, so the signal
    # takes a fresh one before it is re-armed.
    def rearm_raise(exc, outer)
      retain_if_heap(addr_of(exc))
      f.ins "call #{f.import("zeo_rt_signal_set")}(#{f.iconst("i8", Capi::SIGNAL_RAISE)}, #{addr_of(exc)})"
      f.ins "jump #{outer}"
    end

    # `value rescue fallback`: one bare clause over one expression. A bare
    # clause is `StandardError`, so anything above it still leaves.
    def lower_rescue_modifier(node)
      outer = scope.raise_block
      landing, done = f.label, f.label
      result = f.slot
      store_nil(addr_of(result))

      scope.raise_block = landing
      value = lower_expr(node.expression)
      scope.raise_block = outer
      unless f.terminated?
        move(value, addr_of(result))
        f.ins "jump #{done}"
      end

      f.switch(landing)
      exc = take_raised(outer)
      matched = matches_any([constant_named("StandardError")], exc, outer)
      body, miss = f.label, f.label
      f.ins "brif #{matched}, #{body}, #{miss}"
      f.switch(body)
      lower_rescue_body(nil, exc, outer, result, done) { lower_expr(node.rescue_expression) }
      f.switch(miss)
      rearm_raise(exc, outer)
      f.switch(done)
      Operand.new(result, true, false)
    end

    # Whether one clause catches this exception. `rescue` matches with
    # `Module#===`, so the listed classes are ordinary expressions and a
    # bare clause is `StandardError` read like any other constant -- no
    # class id is needed, and a builtin matches the same as a declared one.
    def clause_matches(clause, exc, outer)
      listed = clause.exceptions.map do |e|
        raise Unsupported.new(e, "a splat in a rescue clause") if e.is_a?(Prism::SplatNode)

        lower_expr(e)
      end
      listed = [constant_named("StandardError")] if listed.empty?
      matches_any(listed, exc, outer)
    end

    # Whether any of `listed` catches `exc`, by `Module#===`.
    def matches_any(listed, exc, outer)
      hit = f.slot(1)
      status = f.val(
        "call #{f.import("zeo_rt_rescue_matches_any")}(#{addr_of(exc)}, " \
        "#{value_array(listed)}, #{addr_of(hit)})",
      )
      # A matcher can raise -- an undefined constant, or a listed value
      # that is not a Module -- and that raise leaves this begin.
      cont = f.label
      f.ins "brif #{status}, #{outer}, #{cont}"
      f.switch(cont)
      f.val("load.i8 notrap aligned #{addr_of(hit)}")
    end

    # One clause's body, with `$!` held for its whole run. The pop happens
    # on both exits, and `lower_return` and friends pay what they owe.
    def lower_rescue_body(reference, exc, outer, result, done)
      f.ins "call #{f.import("zeo_rt_handling_push")}(#{addr_of(exc)})"
      scope.handling_depth += 1
      bind_rescue_reference(reference, exc)
      clause_land = f.label
      scope.raise_block = clause_land
      value = yield
      scope.raise_block = outer
      unless f.terminated?
        move(value, addr_of(result))
        f.ins "call #{f.import("zeo_rt_handling_pop")}()"
        f.ins "jump #{done}"
      end
      scope.handling_depth -= 1
      f.switch(clause_land)
      f.ins "call #{f.import("zeo_rt_handling_pop")}()"
      f.ins "jump #{outer}"
    end

    # `rescue Foo => e` binds the exception, borrowed: the pool owns it.
    def bind_rescue_reference(node, exc)
      case node
      when nil then nil
      when Prism::LocalVariableTargetNode
        store_local(local(node), Operand.new(exc, false, false))
      else raise Unsupported.new(node, "a rescue binding of that shape")
      end
    end

    # The `handling_pop`s a direct jump out of this scope owes. A jump to
    # a landing INSIDE the scope leaves only the clauses opened since,
    # which is what `down_to` names. The lexical counter stays put: the
    # pops are per path.
    def pop_handling(down_to = 0)
      (scope.handling_depth - down_to).times { f.ins "call #{f.import("zeo_rt_handling_pop")}()" }
    end

    # `super` resumes the MRO walk above the class the `def` was WRITTEN
    # in, never above the receiver's own class. Every class contributes a
    # row per instance method it writes, which the backend derives from
    # the `def`s, and this call walks them.
    #
    # `args` is the written argument list, or nil for a bare `super`,
    # which forwards the method's parameters -- by their CURRENT values,
    # as ruby does, so reassigning one before the call sends the new one.
    def lower_super(node, args)
      definition = enclosing_definition
      raise Unsupported.new(node, "a super outside a method body") if definition.nil?

      # A body the runtime installed lands on a class minted while the
      # program ran, so its target is read off the method-frame stack
      # rather than named here.
      runtime = definition[:runtime]
      raise Unsupported.new(node, "a super at the top level") if !runtime && owner == Names::OBJECT

      into = f.slot
      builder = block_builder(node)
      argv, kw = super_arguments(args, definition)
      blk = builder ? builder.call : forwarded_block
      status = f.val(super_call(definition, runtime, argv, kw, blk, addr_of(into)))
      builder ? catch_break(status, addr_of(into)) : status_check(status)
      Operand.new(into, true, false)
    end

    # The `def` a `super` written HERE belongs to. A block body has no
    # definition of its own and a `super` in one is the enclosing
    # method's, so the search walks out through blocks -- and stops at
    # the top level or a class body, where ruby has no `super` either.
    def enclosing_definition
      @scopes.reverse_each do |s|
        return s.definition if s.kind == :body
        return nil unless s.kind == :block
      end
      nil
    end

    # Which of the three `super` entries this site takes. A class method
    # resolves against the SINGLETON-class chain, which the runtime walks
    # from the class the `def self.x` was written in.
    def super_call(definition, runtime, argv, kw, blk, into)
      tail = "#{argv}, #{f.iconst("i8", 0)}, #{kw}, #{blk}, #{into}"
      name = sym_id(definition[:node].name)
      if runtime
        "call #{f.import("zeo_rt_send_super_dynamic_args")}(#{borrow(self_operand)}, #{tail})"
      elsif definition[:singleton]
        "call #{f.import("zeo_rt_send_super_class_from_args")}(#{class_id(owner)}, " \
          "#{class_id(owner)}, #{name}, #{tail})"
      else
        "call #{f.import("zeo_rt_send_super_from_args")}(#{borrow(self_operand)}, " \
          "#{class_id(owner)}, #{name}, #{tail})"
      end
    end

    # A `super`'s argument Array and its keyword Hash, or a null pointer
    # where no keywords were written. The runtime reads an Array rather
    # than a slot array, which is what lets a `*` splat be one different
    # push and nothing else.
    def super_arguments(args, definition)
      args = args&.dup
      return forwarded_arguments(definition[:params]) if args.nil?

      keywords = args.pop if args.last.is_a?(Prism::KeywordHashNode)
      argv = new_array(args.size)
      args.each { |a| push_call_argument(argv, a) }
      [argv, keywords ? borrow(hash_literal(keywords)) : f.iconst("i64", 0)]
    end

    # One written argument, pushed onto the call's Array. A `*` splat
    # spreads its elements in and `...` spreads the rest it was handed;
    # everything else is one value.
    def push_call_argument(argv, node)
      case node
      when Prism::SplatNode
        # A bare `*` forwards the anonymous rest parameter, which binds
        # the `*` slot.
        return push_splat(argv, read_local(locals.fetch(:*))) if node.expression.nil?

        push_splat(argv, lower_expr(node.expression))
      when Prism::ForwardingArgumentsNode then push_splat(argv, read_local(locals.fetch(:*)))
      when Prism::KeywordHashNode, Prism::BlockArgumentNode
        raise Unsupported.new(node, "an argument of that shape")
      else push_argument(argv, lower_expr(node))
      end
    end

    # A bare `super`'s arguments: the method's own parameters, read back
    # out of their locals in slot order, by their CURRENT values. A rest
    # spreads and the keywords rebuild the Hash the method was handed.
    def forwarded_arguments(params)
      argv = new_array(params.required.size + params.optional.size + params.post.size)
      params.required.each { |n| push_argument(argv, read_local(locals.fetch(n))) }
      params.optional.each { |o| push_argument(argv, read_local(locals.fetch(o.name))) }
      push_splat(argv, read_local(locals.fetch(params.rest.name))) if params.rest&.named?
      params.post.each { |n| push_argument(argv, read_local(locals.fetch(n))) }
      [argv, forwarded_keywords(params)]
    end

    # The keyword Hash a bare `super` rebuilds, or a null pointer where
    # the method declares no keyword channel at all.
    def forwarded_keywords(params)
      return f.iconst("i64", 0) if params.keywords.empty? && !params.kwrest&.named?

      slot = f.slot
      at = addr_of(slot)
      f.ins "call #{f.import("zeo_rt_hash_new")}(#{at})"
      f.ins "call #{f.import("zeo_rt_pool_push")}(#{at})"
      params.keywords.each do |k|
        key = hand_over(literal_symbol(k.name))
        value = hand_over(read_local(locals.fetch(k.name)))
        status_check(f.val("call #{f.import("zeo_rt_hash_set")}(#{at}, #{key}, #{value})"))
      end
      if params.kwrest&.named?
        status_check(f.val(
          "call #{f.import("zeo_rt_kw_splat_into")}(#{at}, " \
          "#{borrow(read_local(locals.fetch(params.kwrest.name)))})",
        ))
      end
      at
    end

    # An Array of values in a pooled slot, which a runtime entry reads
    # instead of the slot array an ordinary send takes.
    def value_array(operands)
      argv = new_array(operands.size)
      operands.each { |o| push_argument(argv, o) }
      argv
    end

    # A fresh, pooled Array with room for `size` elements.
    def new_array(size)
      slot = f.slot
      at = addr_of(slot)
      f.ins "call #{f.import("zeo_rt_array_new")}(#{f.iconst("i64", size)}, #{at})"
      f.ins "call #{f.import("zeo_rt_pool_push")}(#{at})"
      at
    end

    def push_argument(argv, operand)
      f.ins "call #{f.import("zeo_rt_array_push")}(#{argv}, #{hand_over(operand)})"
    end

    # `*value` spread in place, through ruby's `to_a` rule.
    def push_splat(argv, operand)
      status_check(f.val("call #{f.import("zeo_rt_array_push_splat")}(#{argv}, #{borrow(operand)})"))
    end

    # With no block written at the `super`, the method's own goes on --
    # which, in a block, is the enclosing method's, the same channel a
    # bare `yield` there reads. The callee consumes a reference and this
    # frame's epilogue releases its own, so the forward takes a fresh one.
    def forwarded_block
      blk = yield_block
      return f.iconst("i64", 0) if blk.nil?

      has = f.val("icmp ne #{blk}, #{f.iconst("i64", 0)}")
      yes, no = f.label, f.label
      f.ins "brif #{has}, #{yes}, #{no}"
      f.switch(yes)
      f.ins "call #{f.import("zeo_rt_retain")}(#{blk})"
      f.ins "jump #{no}"
      f.switch(no)
      blk
    end

    # The block a bare `yield` reaches: this scope's own, or -- inside a
    # block -- the enclosing method's, which the proc carried along as its
    # `ProcEnv.lexical_blk`. Hoisted, because the scattered uses have no
    # block in common: a `->` in one branch and a `yield` in another both
    # want it, and neither dominates the other.
    def yield_block
      return scope.blk if scope.blk
      return nil if scope.env.nil?

      f.hoisted([:lexical_blk]) { "load.i64 notrap aligned #{scope.env}+#{Capi::PROC_ENV_LEXICAL_BLK}" }
    end

    # `block_given?` is the block pointer against null -- no call at all.
    def block_given(node)
      blk = yield_block
      raise Unsupported.new(node, "a block_given? outside a method that takes a block") if blk.nil?

      slot = f.slot
      at = addr_of(slot)
      has = f.val("icmp ne #{blk}, #{f.iconst("i64", 0)}")
      f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_BOOL)}, #{at}"
      f.ins "store notrap aligned #{has}, #{at}+8"
      Operand.new(slot, false, true)
    end

    # Inside a loop, `next` starts the next iteration and its value is
    # discarded; inside a block it is not a signal at all but the block's
    # ordinary return, with its value in the out slot.
    def lower_next(node)
      if (loop = scope.loops.last)
        return signal_jump(node, Capi::SIGNAL_NEXT) unless loop.depth == scope.ensure_depth

        discard(one_value(node))
        pop_handling(loop.handling)
        f.ins "call #{f.import("zeo_rt_pool_reset")}(#{loop.mark})"
        f.ins "jump #{loop.head}"
        return unreachable
      end
      raise Unsupported.new(node, "a next outside a block or a loop") unless kind == :block
      return signal_jump(node, Capi::SIGNAL_NEXT) if scope.ensure_depth.positive?

      move(one_value(node), out)
      pop_handling
      f.ins "jump #{done_block}"
      unreachable
    end

    # Inside a loop, `break` leaves it and the loop answers the value;
    # inside a block it arms the Break signal and leaves, and the send
    # that passed the block takes the value and answers it.
    def lower_break(node)
      if (loop = scope.loops.last)
        return signal_jump(node, Capi::SIGNAL_BREAK) unless loop.depth == scope.ensure_depth

        move(one_value(node), addr_of(loop.result))
        pop_handling(loop.handling)
        f.ins "jump #{loop.done}"
        return unreachable
      end
      raise Unsupported.new(node, "a break outside a block or a loop") unless kind == :block

      value = hand_over(one_value(node))
      pop_handling
      f.ins "call #{f.import("zeo_rt_signal_set")}(#{f.iconst("i8", Capi::SIGNAL_BREAK)}, #{value})"
      f.ins "jump #{raise_block}"
      unreachable
    end

    # `redo` runs the body again: a loop's without stepping, and a
    # block's past the bindings -- ruby does not re-yield, so the
    # parameters keep whatever the body assigned to them.
    def lower_redo(node)
      if (loop = scope.loops.last)
        return signal_jump(node, Capi::SIGNAL_REDO, value: false) unless loop.depth == scope.ensure_depth

        pop_handling(loop.handling)
        f.ins "jump #{loop.body}"
        return unreachable
      end
      raise Unsupported.new(node, "a redo outside a block or a loop") if scope.redo_block.nil?
      return signal_jump(node, Capi::SIGNAL_REDO, value: false) if scope.ensure_depth.positive?

      pop_handling
      f.ins "jump #{scope.redo_block}"
      unreachable
    end

    # A jump that cannot reach its target from here travels as a signal
    # instead: every `ensure` between the two runs its clause, and the
    # innermost one turns the signal back into the jump it was.
    def signal_jump(node, signal, value: true)
      # `redo` carries nothing; the other three answer nil without one.
      payload = value ? hand_over(one_value(node)) : f.iconst("i64", 0)
      f.ins "call #{f.import("zeo_rt_signal_set")}(#{f.iconst("i8", signal)}, #{payload})"
      scope.ensure_jumps += 1
      f.ins "jump #{raise_block}"
      unreachable
    end

    # The single value of a `return`, `next` or `break`, or nil. More
    # than one, or a lone `*xs`, is ruby's one Array.
    def one_value(node)
      args = node.arguments&.arguments || []
      return literal_nil if args.empty?
      return lower_expr(args[0]) if args.size == 1 && !args[0].is_a?(Prism::SplatNode)

      values_array(args)
    end

    # The Array a jump carrying several values answers. Pooled at
    # creation, so an element that raises mid-build strands nothing.
    def values_array(args)
      slot = f.slot
      at = addr_of(slot)
      f.ins "call #{f.import("zeo_rt_array_new")}(#{f.iconst("i64", args.size)}, #{at})"
      f.ins "call #{f.import("zeo_rt_pool_push")}(#{at})"
      args.each { |a| push_call_argument(at, a) }
      Operand.new(slot, false, false)
    end

    # Nothing runs after a jump; the slot is never written or read.
    def unreachable
      Operand.new(f.slot, false, true)
    end

    # `return` leaves the method that wrote it. A lambda counts as one --
    # its `return` is its own -- and everywhere else the value travels as
    # a signal: the runtime aims it at the activation the proc captured,
    # whose boundary folds it, and a dead one answers LocalJumpError. An
    # `ensure` in the way makes even a method's own return travel, so the
    # clause runs before the caller sees the value.
    def lower_return(node)
      raise Unsupported.new(node, "a return outside a def") unless kind == :body || kind == :block
      return signal_jump(node, Capi::SIGNAL_RETURN) if kind == :block && !scope.lambda?
      return signal_jump(node, Capi::SIGNAL_RETURN) if scope.ensure_depth.positive?

      # The value is read BEFORE `$!` unwinds, so `return $!.message`
      # inside a rescue clause answers the one it caught.
      move(one_value(node), out)
      pop_handling
      f.ins "jump #{done_block}"
      unreachable
    end

    # ---- values and ownership ----

    def addr_of(operand_or_slot)
      at = operand_or_slot.is_a?(Operand) ? operand_or_slot.at : operand_or_slot
      at.start_with?("ss") ? f.stack_addr(at) : at
    end

    def store_nil(at)
      zero = f.iconst("i64", 0)
      f.ins "store notrap aligned #{zero}, #{at}"
      f.ins "store notrap aligned #{zero}, #{at}+8"
      f.ins "store notrap aligned #{zero}, #{at}+16"
    end

    def copy(from, to)
      [0, 8, 16].each do |off|
        word = f.val("load.i64 notrap aligned #{from}#{off.zero? ? "" : "+#{off}"}")
        f.ins "store notrap aligned #{word}, #{to}#{off.zero? ? "" : "+#{off}"}"
      end
    end

    def tag_of(at)
      f.val("load.i8 notrap aligned #{at}")
    end

    # `call sym(at)` only when the value at `at` is a heap object.
    def if_heap(at, sym)
      heap = f.val("icmp uge #{tag_of(at)}, #{f.iconst("i8", Capi::TAG_HEAP)}")
      yes, no = f.label, f.label
      f.ins "brif #{heap}, #{yes}, #{no}"
      f.switch(yes)
      f.ins "call #{f.import(sym)}(#{at})"
      f.ins "jump #{no}"
      f.switch(no)
    end

    def retain_if_heap(at) = if_heap(at, "zeo_rt_retain")
    def release_if_heap(at) = if_heap(at, "zeo_rt_release")

    # An address to read `value` through without taking it: an owned
    # temporary goes to the pool first, so the frame or the statement
    # releases it.
    def borrow(value)
      at = addr_of(value)
      if value.owned && !value.immediate
        if_heap(at, "zeo_rt_pool_push")
        value.owned = false
      end
      at
    end

    # An address whose value the callee TAKES. An unowned value is
    # retained first, because whoever held it keeps its own reference.
    def hand_over(value)
      at = addr_of(value)
      retain_if_heap(at) if !value.owned && !value.immediate
      value.owned = false
      at
    end

    # `value` into the slot at `to`, which then owns it.
    def move(value, to)
      copy(hand_over(value), to)
    end

    def discard(value)
      borrow(value)
    end

    def truthy(value)
      f.val("call #{f.import("zeo_rt_truthy")}(#{borrow(value)})")
    end

    # A pointer into rodata and the byte length, for `text`.
    def rodata_ref(text)
      off = @program.intern(text)
      ptr = off.zero? ? rodata : f.val("iadd.i64 #{rodata}, #{f.iconst("i64", off)}")
      [ptr, f.iconst("i64", text.bytesize)]
    end

    def status_check(status)
      cont = f.label
      f.ins "brif #{status}, #{raise_block}, #{cont}"
      f.switch(cont)
    end
  end
end
