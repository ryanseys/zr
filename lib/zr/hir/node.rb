# frozen_string_literal: true

require_relative "../record"

module Zr
  # The high-level IR: a tree of Ruby-level nodes, desugared and
  # name-resolved, that every lowering reads instead of Prism. One class
  # per kind; `line` is where the node starts; `locals` lists every local
  # of a scope, parameters first.
  module Hir
    # The slot of a block's implicit `it`. No program can spell it, so
    # `parameters` and `local_variables` leave it out, as CRuby does.
    IT = :"%it"

    # `units` are the files a require or load reaches, each a toplevel
    # of its own, in the order they were first named. `warnings` are the
    # parse-time warnings ruby prints for the file, printed when it runs.
    # `evals` says the program carries the compiler; `entries` maps each
    # file path to its unit: an index into `units`, or the entry of a
    # road built already.
    # `traced` says the program names TracePoint, so its code fires the
    # events a TracePoint asks for.
    # `node_ids` maps a HIR node, by identity, to the prism node id it
    # came from.
    # `spots` holds each file's error_highlight spots (Hir::Spots), by
    # the file name its frames carry.
    # `activations` is how many `using` rows this program holds, which a
    # build at run time takes its own rows after.
    # `branches` holds each measured file's branch rows, by file name, in
    # the order Coverage numbers them, and `defs` each file's def and
    # block spans, which a definition claims to become a method row.
    class Program < ::Zr::Record
      FIELDS = %i[file locals body units warnings evals entries traced node_ids spots coverable activations branches
                  defs].freeze
      attr_accessor :file, :locals, :body, :units, :warnings, :evals, :entries, :traced, :node_ids, :spots, :coverable,
                    :activations, :branches, :defs

      def initialize(file = nil, locals = nil, body = nil, units = nil, warnings = nil, evals = nil, entries = nil, traced = nil,
                     node_ids = nil, spots = nil, coverable = nil, activations = nil, branches = nil, defs = nil)
        @file = file
        @locals = locals
        @body = body
        @units = units
        @warnings = warnings
        @evals = evals
        @entries = entries
        @traced = traced
        @node_ids = node_ids
        @spots = spots
        @coverable = coverable
        @activations = activations
        @branches = branches
        @defs = defs
      end

      def to_a = [@file, @locals, @body, @units, @warnings, @evals, @entries, @traced, @node_ids, @spots, @coverable,
                  @activations, @branches, @defs]
    end
    # `hidden` when the unit loads only for the runtime's own use, as the
    # eval road's files do.
    # `source` is the bytes the unit was built from, and `activates`
    # says the file took an activation row for a `using`: both are what
    # the unit cache is keyed on (lib/zr/unit_cache.rb). The bytes and
    # not a digest of them, because the loader runs inside a program
    # that evals as well, and nothing there may reach for a library the
    # loader would then have to load.
    class Unit < ::Zr::Record
      FIELDS = %i[file locals body warnings internal spots hidden source activates].freeze
      attr_accessor :file, :locals, :body, :warnings, :internal, :spots, :hidden, :source, :activates

      def initialize(file = nil, locals = nil, body = nil, warnings = nil, internal = nil, spots = nil, hidden = nil,
                     source = nil, activates = nil)
        @file = file
        @locals = locals
        @body = body
        @warnings = warnings
        @internal = internal
        @spots = spots
        @hidden = hidden
        @source = source
        @activates = activates
      end

      def to_a = [@file, @locals, @body, @warnings, @internal, @spots, @hidden, @source, @activates]
    end
    # `require`, `require_relative` or `load` of a literal name: `path`
    # is the file it resolved to and `unit` that file's index, or both
    # nil when no file answers.
    class Require < ::Zr::Record
      FIELDS = %i[kind feature path unit line].freeze
      attr_accessor :kind, :feature, :path, :unit, :line

      def initialize(kind = nil, feature = nil, path = nil, unit = nil, line = nil)
        @kind = kind
        @feature = feature
        @path = path
        @unit = unit
        @line = line
      end

      def to_a = [@kind, @feature, @path, @unit, @line]
    end

    # The `using` rows a program holds, taken before its first line runs
    # so that a build at run time can take the rows after them. Only a
    # program that carries the compiler needs it: nothing else compiles
    # anything once it has started.
    class Activations < ::Zr::Record
      FIELDS = %i[count line].freeze
      attr_accessor :count, :line

      def initialize(count = nil, line = nil)
        @count = count
        @line = line
      end

      def to_a = [@count, @line]
    end

    # A form this runtime does not answer, held until the program runs
    # it. Reaching it stops the program by name; never reaching it costs
    # nothing.
    class Stop < ::Zr::Record
      FIELDS = %i[what line].freeze
      attr_accessor :what, :line

      def initialize(what = nil, line = nil)
        @what = what
        @line = line
      end

      def to_a = [@what, @line]
    end
    # `autoload :Name, "feature"` on `recv` (nil for self): the file is
    # `path`, unit `unit`; it runs when the constant is first read.
    # `declared` is an autoload of a feature a require would read no
    # file for: the name is declared and no row is kept, so nothing
    # waits for a file and `autoload?` answers nil.
    class Autoload < ::Zr::Record
      FIELDS = %i[recv name feature path unit line declared].freeze
      attr_accessor :recv, :name, :feature, :path, :unit, :line, :declared

      def initialize(recv = nil, name = nil, feature = nil, path = nil, unit = nil, line = nil, declared = nil)
        @recv = recv
        @name = name
        @feature = feature
        @path = path
        @unit = unit
        @line = line
        @declared = declared
      end

      def to_a = [@recv, @name, @feature, @path, @unit, @line, @declared]
    end
    # A statement list; its value is the last statement's.
    class Seq < ::Zr::Record
      FIELDS = %i[stmts line].freeze
      attr_accessor :stmts, :line

      def initialize(stmts = nil, line = nil)
        @stmts = stmts
        @line = line
      end

      def to_a = [@stmts, @line]
    end
    # A method call. `recv` is nil for an implicit self; `vcall` marks a
    # bare identifier, which is a NameError when nothing answers; `opt`
    # marks the operator syntax `recv[i]`, `recv[i] = v` and `recv << v`,
    # which CRuby runs without a frame on its builtin receivers. An
    # argument may be a Splat; `kwargs` is a HashLit passed as keywords,
    # or nil; `block` is a Block literal, a BlockPass, or nil.
    # `using` is the activation row in force where the call is written,
    # nil where no refinement is.
    # `covers` is a safe call's two branches, `[then, else]`, which
    # Coverage counts where a receiver was and was not nil; nil for
    # every other call.
    class Send < ::Zr::Record
      FIELDS = %i[recv name args line vcall opt block kwargs safe write using covers].freeze
      attr_accessor :recv, :name, :args, :line, :vcall, :opt, :block, :kwargs, :safe, :write, :using, :covers

      def initialize(recv = nil, name = nil, args = nil, line = nil, vcall = nil, opt = nil, block = nil, kwargs = nil,
                     safe = nil, write = nil, using = nil, covers = nil)
        @recv = recv
        @name = name
        @args = args
        @line = line
        @vcall = vcall
        @opt = opt
        @block = block
        @kwargs = kwargs
        @safe = safe
        @write = write
        @using = using
        @covers = covers
      end

      def to_a = [@recv, @name, @args, @line, @vcall, @opt, @block, @kwargs, @safe, @write, @using, @covers]
    end

    # `using mod`: row `id` holds what row `from` held plus every
    # refinement `mod` carries. `from` is -1 where nothing was in use.
    class Using < ::Zr::Record
      FIELDS = %i[id from value line].freeze
      attr_accessor :id, :from, :value, :line

      def initialize(id = nil, from = nil, value = nil, line = nil)
        @id = id
        @from = from
        @value = value
        @line = line
      end

      def to_a = [@id, @from, @value, @line]
    end
    # Before a statement that holds a `using` a condition may skip: each
    # `[id, from]` row holds what row `from` held until its `using` runs.
    class UsingDefaults < ::Zr::Record
      FIELDS = %i[rows line].freeze
      attr_accessor :rows, :line

      def initialize(rows = nil, line = nil)
        @rows = rows
        @line = line
      end

      def to_a = [@rows, @line]
    end
    # A value the lowering has already put in record slot `index`: the
    # lowering's own node, for a receiver or argument evaluated once.
    class Slot < ::Zr::Record
      FIELDS = %i[index line].freeze
      attr_accessor :index, :line

      def initialize(index = nil, line = nil)
        @index = index
        @line = line
      end

      def to_a = [@index, @line]
    end
    # `recv[args] op= value` and `recv.name op= value`, the receiver and
    # arguments evaluated once; `op` is an operator, or :or / :and.
    # `using` is the refinements in force, as a Send's, for each of the
    # sends it makes.
    class IndexOpAssign < ::Zr::Record
      FIELDS = %i[recv args op value line using].freeze
      attr_accessor :recv, :args, :op, :value, :line, :using

      def initialize(recv = nil, args = nil, op = nil, value = nil, line = nil, using = nil)
        @recv = recv
        @args = args
        @op = op
        @value = value
        @line = line
        @using = using
      end

      def to_a = [@recv, @args, @op, @value, @line, @using]
    end
    # `safe` is `recv&.name op= value`: nil, with nothing else run,
    # when the receiver is nil.
    class AttrOpAssign < ::Zr::Record
      FIELDS = %i[recv name op value line safe using].freeze
      attr_accessor :recv, :name, :op, :value, :line, :safe, :using

      def initialize(recv = nil, name = nil, op = nil, value = nil, line = nil, safe = nil, using = nil)
        @recv = recv
        @name = name
        @op = op
        @value = value
        @line = line
        @safe = safe
        @using = using
      end

      def to_a = [@recv, @name, @op, @value, @line, @safe, @using]
    end
    # `*value` among arguments or elements.
    class Splat < ::Zr::Record
      FIELDS = %i[value line].freeze
      attr_accessor :value, :line

      def initialize(value = nil, line = nil)
        @value = value
        @line = line
      end

      def to_a = [@value, @line]
    end
    # `**value` among a hash literal's pairs: the key, with a nil value.
    class HashSplat < ::Zr::Record
      FIELDS = %i[value line].freeze
      attr_accessor :value, :line

      def initialize(value = nil, line = nil)
        @value = value
        @line = line
      end

      def to_a = [@value, @line]
    end
    # `&value`: the block a call passes on.
    class BlockPass < ::Zr::Record
      FIELDS = %i[value line].freeze
      attr_accessor :value, :line

      def initialize(value = nil, line = nil)
        @value = value
        @line = line
      end

      def to_a = [@value, @line]
    end
    # A block literal: its parameters, every local of its scope
    # (parameters first), and its body.
    class Block < ::Zr::Record
      FIELDS = %i[params locals body line end_line cover].freeze
      attr_accessor :params, :locals, :body, :line, :end_line, :cover

      def initialize(params = nil, locals = nil, body = nil, line = nil, end_line = nil, cover = nil)
        @params = params
        @locals = locals
        @body = body
        @line = line
        @end_line = end_line
        @cover = cover
      end

      def to_a = [@params, @locals, @body, @line, @end_line, @cover]
    end
    # `-> (params) { body }`: a Block that is a lambda from the start.
    class Lambda < ::Zr::Record
      FIELDS = %i[block line].freeze
      attr_accessor :block, :line

      def initialize(block = nil, line = nil)
        @block = block
        @line = line
      end

      def to_a = [@block, @line]
    end
    # The one parameter shape: `required` and `post` are names,
    # `optional` and `keywords` are `[name, default]` pairs (a keyword
    # with no default is required), `rest`, `kwrest` and `block` are a
    # name or nil; a block's `|a, |` has the rest `:implicit`.
    class Params < ::Zr::Record
      FIELDS = %i[required optional rest post keywords kwrest block].freeze
      attr_accessor :required, :optional, :rest, :post, :keywords, :kwrest, :block

      def initialize(required = nil, optional = nil, rest = nil, post = nil, keywords = nil, kwrest = nil, block = nil)
        @required = required
        @optional = optional
        @rest = rest
        @post = post
        @keywords = keywords
        @kwrest = kwrest
        @block = block
      end

      def to_a = [@required, @optional, @rest, @post, @keywords, @kwrest, @block]

      def positional
        required.size + optional.size + post.size
      end

      # Whether a lone Array argument spreads over the parameters, as
      # CRuby's block setup decides: a required parameter or two or more
      # optional ones ask for it; a lone `|a|` does not, nor keywords
      # beside exactly one positional and no rest.
      def spread?
        min = required.size + post.size
        keyworded = !keywords.empty? || !kwrest.nil?
        return false if positional == 1 && rest.nil? && (min == 1 || keyworded)

        min.positive? || optional.size > 1
      end

      # Only required parameters: the exact arity a dispatcher may check.
      def plain?
        optional.empty? && rest.nil? && post.empty? && keywords.empty? && kwrest.nil?
      end

      def names
        positionals = (required + post).flat_map { |r| r.is_a?(MultiTarget) ? r.names : [r] }
        positionals + optional.map(&:first) + [rest].compact + keywords.map(&:first) + [kwrest, block].compact - %i[implicit nokey]
      end

      # `Method#arity`: the required count, negative less one when the
      # count may vary. A required keyword counts as one argument; any
      # other keyword form allows one more.
      def arity
        min = required.size + post.size + (keywords.any? { |_, default| default.nil? } ? 1 : 0)
        return -min - 1 if rest && rest != :implicit

        max = required.size + optional.size + post.size + (keywords.any? || (kwrest && kwrest != :nokey) ? 1 : 0)
        min == max ? min : -min - 1
      end

      # `Method#parameters`, in CRuby's order: `[kind, name]` rows, a
      # destructuring parameter and `it` with no name.
      def rows
        positional = ->(p) { p.is_a?(MultiTarget) || p == IT ? [:req] : [:req, p] }
        [
          *required.map(&positional),
          *optional.map { |name, _| [:opt, name] },
          *(rest && rest != :implicit ? [[:rest, rest]] : []),
          *post.map(&positional),
          *keywords.map { |name, default| [default.nil? ? :keyreq : :key, name] },
          *(kwrest == :nokey ? [[:nokey]] : kwrest ? [[:keyrest, kwrest]] : []),
          *(block ? [[:block, block]] : [])
        ]
      end
    end
    class Yield < ::Zr::Record
      FIELDS = %i[args line kwargs].freeze
      attr_accessor :args, :line, :kwargs

      def initialize(args = nil, line = nil, kwargs = nil)
        @args = args
        @line = line
        @kwargs = kwargs
      end

      def to_a = [@args, @line, @kwargs]
    end
    # `super(args)`; `block` as a Send's. `ZSuper` is the bare `super`,
    # passing the method's own parameters on as they stand. `in_block`
    # marks a bare `super` in a block of a def, which CRuby refuses when
    # the block runs as a method `define_method` made.
    # `using` is the activation in force where the super stands, as on
    # a Send: ruby resolves a super under the refinements of its scope.
    class Super < ::Zr::Record
      FIELDS = %i[args kwargs block line in_block using].freeze
      attr_accessor :args, :kwargs, :block, :line, :in_block, :using

      def initialize(args = nil, kwargs = nil, block = nil, line = nil, in_block = nil, using = nil)
        @args = args
        @kwargs = kwargs
        @block = block
        @line = line
        @in_block = in_block
        @using = using
      end

      def to_a = [@args, @kwargs, @block, @line, @in_block, @using]
    end
    class ZSuper < ::Zr::Record
      FIELDS = %i[block line].freeze
      attr_accessor :block, :line

      def initialize(block = nil, line = nil)
        @block = block
        @line = line
      end

      def to_a = [@block, @line]
    end
    class Break < ::Zr::Record
      FIELDS = %i[value line].freeze
      attr_accessor :value, :line

      def initialize(value = nil, line = nil)
        @value = value
        @line = line
      end

      def to_a = [@value, @line]
    end
    class Next < ::Zr::Record
      FIELDS = %i[value line].freeze
      attr_accessor :value, :line

      def initialize(value = nil, line = nil)
        @value = value
        @line = line
      end

      def to_a = [@value, @line]
    end
    # An Integer, String, Symbol, nil, true or false.
    # `chilled` marks a String literal of a file that sets no
    # frozen_string_literal: the String it makes warns on its first change.
    class Literal < ::Zr::Record
      FIELDS = %i[value line chilled].freeze
      attr_accessor :value, :line, :chilled

      def initialize(value = nil, line = nil, chilled = nil)
        @value = value
        @line = line
        @chilled = chilled
      end

      def to_a = [@value, @line, @chilled]
    end
    class SelfRef < ::Zr::Record
      FIELDS = %i[line].freeze
      attr_accessor :line

      def initialize(line = nil)
        @line = line
      end

      def to_a = [@line]
    end
    # `def name(params) body end`; its value is the name. `params` is a
    # Params; `receiver` is the expression of a singleton def
    # (`def self.x`, `def obj.x`), or nil.
    class Def < ::Zr::Record
      FIELDS = %i[name params locals body line receiver evals end_line cover].freeze
      attr_accessor :name, :params, :locals, :body, :line, :receiver, :evals, :end_line, :cover

      def initialize(name = nil, params = nil, locals = nil, body = nil, line = nil, receiver = nil, evals = nil, end_line = nil,
                     cover = nil)
        @name = name
        @params = params
        @locals = locals
        @body = body
        @line = line
        @receiver = receiver
        @evals = evals
        @end_line = end_line
        @cover = cover
      end

      def to_a = [@name, @params, @locals, @body, @line, @receiver, @evals, @end_line, @cover]
    end
    # `depth` counts block scopes up to the one that holds the local.
    class Local < ::Zr::Record
      FIELDS = %i[name depth line].freeze
      attr_accessor :name, :depth, :line

      def initialize(name = nil, depth = nil, line = nil)
        @name = name
        @depth = depth
        @line = line
      end

      def to_a = [@name, @depth, @line]
    end
    # The point a traced program fires a TracePoint `event` from: a
    # `:line` event, as ruby's compiler places one where a statement
    # starts a new line.
    class Trace < ::Zr::Record
      FIELDS = %i[event line].freeze
      attr_accessor :event, :line

      def initialize(event = nil, line = nil)
        @event = event
        @line = line
      end

      def to_a = [@event, @line]
    end
    # One run of branch `id` in a program Coverage measures. The id is
    # the program's, not the file's: every branch of every file shares
    # one counter array, and `Program#branches` says which rows belong
    # to which file. Its value is nil, so it stands wherever a statement
    # may, including as the else a source never wrote.
    class Cover < ::Zr::Record
      FIELDS = %i[id line].freeze
      attr_accessor :id, :line

      def initialize(id = nil, line = nil)
        @id = id
        @line = line
      end

      def to_a = [@id, @line]
    end
    class Assign < ::Zr::Record
      FIELDS = %i[name depth value line].freeze
      attr_accessor :name, :depth, :value, :line

      def initialize(name = nil, depth = nil, value = nil, line = nil)
        @name = name
        @depth = depth
        @value = value
        @line = line
      end

      def to_a = [@name, @depth, @value, @line]
    end
    # `a, (b, *c), *d, e = value`; its value is the right-hand side's.
    # `taken` is false where nothing takes that value: a statement before
    # the last of a sequence, a loop body.
    class MultiAssign < ::Zr::Record
      FIELDS = %i[target value line taken].freeze
      attr_accessor :target, :value, :line, :taken

      def initialize(target = nil, value = nil, line = nil, taken = nil)
        @target = target
        @value = value
        @line = line
        @taken = taken
      end

      def to_a = [@target, @value, @line, @taken]
    end
    # The targets before the rest, the rest (a target, `:implicit` for a
    # bare `*`, or nil) and the targets after it. A target is an Assign
    # or IvarWrite with a nil value, a Send with the value to append
    # (`h[k]`, `o.attr`), or a nested MultiTarget. As a block parameter,
    # a MultiTarget stands among the required names.
    class MultiTarget < ::Zr::Record
      FIELDS = %i[lefts rest rights line whole].freeze
      attr_accessor :lefts, :rest, :rights, :line, :whole

      def initialize(lefts = nil, rest = nil, rights = nil, line = nil, whole = nil)
        @lefts = lefts
        @rest = rest
        @rights = rights
        @line = line
        @whole = whole
      end

      def to_a = [@lefts, @rest, @rights, @line, @whole]

      def names
        (lefts + [rest] + rights).flat_map do |t|
          case t
          when Assign then [t.name]
          when MultiTarget then t.names
          else []
          end
        end
      end
    end
    # `if`; `unless` arrives with its arms swapped. An arm may be nil.
    class If < ::Zr::Record
      FIELDS = %i[cond yes no line].freeze
      attr_accessor :cond, :yes, :no, :line

      def initialize(cond = nil, yes = nil, no = nil, line = nil)
        @cond = cond
        @yes = yes
        @no = no
        @line = line
      end

      def to_a = [@cond, @yes, @no, @line]
    end
    # `body_first` is a `begin ... end while cond`: the body runs once
    # before the first test.
    class While < ::Zr::Record
      FIELDS = %i[cond body line body_first].freeze
      attr_accessor :cond, :body, :line, :body_first

      def initialize(cond = nil, body = nil, line = nil, body_first = nil)
        @cond = cond
        @body = body
        @line = line
        @body_first = body_first
      end

      def to_a = [@cond, @body, @line, @body_first]
    end
    class Return < ::Zr::Record
      FIELDS = %i[value line].freeze
      attr_accessor :value, :line

      def initialize(value = nil, line = nil)
        @value = value
        @line = line
      end

      def to_a = [@value, @line]
    end
    # `a && b`, `a || b`, `!a`: on truthiness, short circuit.
    class And < ::Zr::Record
      FIELDS = %i[left right line].freeze
      attr_accessor :left, :right, :line

      def initialize(left = nil, right = nil, line = nil)
        @left = left
        @right = right
        @line = line
      end

      def to_a = [@left, @right, @line]
    end
    class Or < ::Zr::Record
      FIELDS = %i[left right line].freeze
      attr_accessor :left, :right, :line

      def initialize(left = nil, right = nil, line = nil)
        @left = left
        @right = right
        @line = line
      end

      def to_a = [@left, @right, @line]
    end
    class Not < ::Zr::Record
      FIELDS = %i[value line].freeze
      attr_accessor :value, :line

      def initialize(value = nil, line = nil)
        @value = value
        @line = line
      end

      def to_a = [@value, @line]
    end
    # A class or module the core defines, read from the runtime and never
    # through lexical scope: what a desugaring names (`Array` in a
    # pattern), so a program's own `Array` cannot stand in for it.
    class Core < ::Zr::Record
      FIELDS = %i[name line].freeze
      attr_accessor :name, :line

      def initialize(name = nil, line = nil)
        @name = name
        @line = line
      end

      def to_a = [@name, @line]
    end
    # A body that runs the first time its site is reached and never again
    # (CRuby's `once` instruction), as `END { }` registers.
    class Once < ::Zr::Record
      FIELDS = %i[body line].freeze
      attr_accessor :body, :line

      def initialize(body = nil, line = nil)
        @body = body
        @line = line
      end

      def to_a = [@body, @line]
    end
    # `class Name < superclass; body; end`. `scope` is nil for a bare
    # name, `:top` for `::Name`, else the expression before `::`.
    class ClassDef < ::Zr::Record
      FIELDS = %i[scope name superclass locals body line end_line].freeze
      attr_accessor :scope, :name, :superclass, :locals, :body, :line, :end_line

      def initialize(scope = nil, name = nil, superclass = nil, locals = nil, body = nil, line = nil, end_line = nil)
        @scope = scope
        @name = name
        @superclass = superclass
        @locals = locals
        @body = body
        @line = line
        @end_line = end_line
      end

      def to_a = [@scope, @name, @superclass, @locals, @body, @line, @end_line]
    end
    class ModuleDef < ::Zr::Record
      FIELDS = %i[scope name locals body line end_line].freeze
      attr_accessor :scope, :name, :locals, :body, :line, :end_line

      def initialize(scope = nil, name = nil, locals = nil, body = nil, line = nil, end_line = nil)
        @scope = scope
        @name = name
        @locals = locals
        @body = body
        @line = line
        @end_line = end_line
      end

      def to_a = [@scope, @name, @locals, @body, @line, @end_line]
    end
    # `class << target; body; end`: the body runs with the singleton
    # class as self and as the definee.
    class SingletonClassDef < ::Zr::Record
      FIELDS = %i[target locals body line end_line].freeze
      attr_accessor :target, :locals, :body, :line, :end_line

      def initialize(target = nil, locals = nil, body = nil, line = nil, end_line = nil)
        @target = target
        @locals = locals
        @body = body
        @line = line
        @end_line = end_line
      end

      def to_a = [@target, @locals, @body, @line, @end_line]
    end
    class ConstRead < ::Zr::Record
      FIELDS = %i[scope name line].freeze
      attr_accessor :scope, :name, :line

      def initialize(scope = nil, name = nil, line = nil)
        @scope = scope
        @name = name
        @line = line
      end

      def to_a = [@scope, @name, @line]
    end
    class ConstWrite < ::Zr::Record
      FIELDS = %i[scope name value line].freeze
      attr_accessor :scope, :name, :value, :line

      def initialize(scope = nil, name = nil, value = nil, line = nil)
        @scope = scope
        @name = name
        @value = value
        @line = line
      end

      def to_a = [@scope, @name, @value, @line]
    end
    class IvarRead < ::Zr::Record
      FIELDS = %i[name line].freeze
      attr_accessor :name, :line

      def initialize(name = nil, line = nil)
        @name = name
        @line = line
      end

      def to_a = [@name, @line]
    end
    class GvarRead < ::Zr::Record
      FIELDS = %i[name line].freeze
      attr_accessor :name, :line

      def initialize(name = nil, line = nil)
        @name = name
        @line = line
      end

      def to_a = [@name, @line]
    end
    # `shown` is the name the program wrote, where it is not `name`.
    class GvarWrite < ::Zr::Record
      FIELDS = %i[name value line shown].freeze
      attr_accessor :name, :value, :line, :shown

      def initialize(name = nil, value = nil, line = nil, shown = nil)
        @name = name
        @value = value
        @line = line
        @shown = shown
      end

      def to_a = [@name, @value, @line, @shown]
    end
    class CvarRead < ::Zr::Record
      FIELDS = %i[name line].freeze
      attr_accessor :name, :line

      def initialize(name = nil, line = nil)
        @name = name
        @line = line
      end

      def to_a = [@name, @line]
    end
    class CvarWrite < ::Zr::Record
      FIELDS = %i[name value line].freeze
      attr_accessor :name, :value, :line

      def initialize(name = nil, value = nil, line = nil)
        @name = name
        @value = value
        @line = line
      end

      def to_a = [@name, @value, @line]
    end
    # `Name ||= value`: set only when unset or falsy.
    class ConstOrWrite < ::Zr::Record
      FIELDS = %i[scope name value line].freeze
      attr_accessor :scope, :name, :value, :line

      def initialize(scope = nil, name = nil, value = nil, line = nil)
        @scope = scope
        @name = name
        @value = value
        @line = line
      end

      def to_a = [@scope, @name, @value, @line]
    end
    # `alias new old`.
    class Alias < ::Zr::Record
      FIELDS = %i[new_name old_name line].freeze
      attr_accessor :new_name, :old_name, :line

      def initialize(new_name = nil, old_name = nil, line = nil)
        @new_name = new_name
        @old_name = old_name
        @line = line
      end

      def to_a = [@new_name, @old_name, @line]
    end
    # `alias $new $old`: one global under two names.
    class GvarAlias < ::Zr::Record
      FIELDS = %i[new_name old_name line].freeze
      attr_accessor :new_name, :old_name, :line

      def initialize(new_name = nil, old_name = nil, line = nil)
        @new_name = new_name
        @old_name = old_name
        @line = line
      end

      def to_a = [@new_name, @old_name, @line]
    end
    # `undef name, ...`.
    class Undef < ::Zr::Record
      FIELDS = %i[names line].freeze
      attr_accessor :names, :line

      def initialize(names = nil, line = nil)
        @names = names
        @line = line
      end

      def to_a = [@names, @line]
    end

    # `alias :"#{a}" :"#{b}"` and `undef :"#{a}"`: the names are values.
    class AliasValue < ::Zr::Record
      FIELDS = %i[new_name old_name line].freeze
      attr_accessor :new_name, :old_name, :line

      def initialize(new_name = nil, old_name = nil, line = nil)
        @new_name = new_name
        @old_name = old_name
        @line = line
      end

      def to_a = [@new_name, @old_name, @line]
    end

    class UndefValue < ::Zr::Record
      FIELDS = %i[names line].freeze
      attr_accessor :names, :line

      def initialize(names = nil, line = nil)
        @names = names
        @line = line
      end

      def to_a = [@names, @line]
    end
    # `defined?(...)`: `kind` names the form (:local, :ivar, :gvar,
    # :cvar, :const, :method, :yield, :super, :self, :nil, :true, :false,
    # :assignment, :expression); `target` is the name, the ConstRead, or
    # the Send the form asks about.
    class Defined < ::Zr::Record
      FIELDS = %i[kind target line].freeze
      attr_accessor :kind, :target, :line

      def initialize(kind = nil, target = nil, line = nil)
        @kind = kind
        @target = target
        @line = line
      end

      def to_a = [@kind, @target, @line]
    end
    # `case subject; when a, b then body; ... else else_body end`. Each
    # clause is `[values, body]`; a nil subject tests each value itself.
    class Case < ::Zr::Record
      FIELDS = %i[subject clauses else_body line].freeze
      attr_accessor :subject, :clauses, :else_body, :line

      def initialize(subject = nil, clauses = nil, else_body = nil, line = nil)
        @subject = subject
        @clauses = clauses
        @else_body = else_body
        @line = line
      end

      def to_a = [@subject, @clauses, @else_body, @line]
    end
    class IvarWrite < ::Zr::Record
      FIELDS = %i[name value line].freeze
      attr_accessor :name, :value, :line

      def initialize(name = nil, value = nil, line = nil)
        @name = name
        @value = value
        @line = line
      end

      def to_a = [@name, @value, @line]
    end
    # `[a, b]`; `frozen` where a `# shareable_constant_value: literal`
    # constant holds it, built frozen with no send (compile.c freezes it
    # in the compiler).
    class ArrayLit < ::Zr::Record
      FIELDS = %i[elements line frozen].freeze
      attr_accessor :elements, :line, :frozen

      def initialize(elements = nil, line = nil, frozen = nil)
        @elements = elements
        @line = line
        @frozen = frozen
      end

      def to_a = [@elements, @line, @frozen]
    end
    # The keywords of an array literal made only of double splats, as an
    # Array to splat: `[h]`, or `[]` when they come out empty, so `[**{}]`
    # adds no element (CRuby's pushtoarraykwsplat).
    class KwSplatElement < ::Zr::Record
      FIELDS = %i[pairs line].freeze
      attr_accessor :pairs, :line

      def initialize(pairs = nil, line = nil)
        @pairs = pairs
        @line = line
      end

      def to_a = [@pairs, @line]
    end
    # `{k => v, ...}`: `pairs` is a flat list, key then value; `frozen`
    # as an ArrayLit's.
    class HashLit < ::Zr::Record
      FIELDS = %i[pairs line frozen].freeze
      attr_accessor :pairs, :line, :frozen

      def initialize(pairs = nil, line = nil, frozen = nil)
        @pairs = pairs
        @line = line
        @frozen = frozen
      end

      def to_a = [@pairs, @line, @frozen]
    end
    # `low..high` / `low...high`; a missing bound is nil.
    # `$1` and the other numbered groups (`kind` :nth, `number` the
    # group, 0 for `$&`), `` $` `` (:pre), `$'` (:post) and `$+` (:last),
    # read from `$~`'s registers, never through MatchData's methods.
    class BackRef < ::Zr::Record
      FIELDS = %i[kind number line].freeze
      attr_accessor :kind, :number, :line

      def initialize(kind = nil, number = nil, line = nil)
        @kind = kind
        @number = number
        @line = line
      end

      def to_a = [@kind, @number, @line]
    end
    # `static` when both ends are Integer or nil literals: one frozen
    # Range for the site.
    class RangeLit < ::Zr::Record
      FIELDS = %i[low high exclusive line static].freeze
      attr_accessor :low, :high, :exclusive, :line, :static

      def initialize(low = nil, high = nil, exclusive = nil, line = nil, static = nil)
        @low = low
        @high = high
        @exclusive = exclusive
        @line = line
        @static = static
      end

      def to_a = [@low, @high, @exclusive, @line, @static]
    end
    # `"a#{b}c"`: literal and expression parts in order.
    class Interp < ::Zr::Record
      FIELDS = %i[parts line].freeze
      attr_accessor :parts, :line

      def initialize(parts = nil, line = nil)
        @parts = parts
        @line = line
      end

      def to_a = [@parts, @line]
    end
    # A regexp literal: its source and option bits; one object per site.
    # `/#{x}/o`: the interpolated regexp its site keeps after the first run.
    class RegexpOnce < ::Zr::Record
      FIELDS = %i[value line].freeze
      attr_accessor :value, :line

      def initialize(value = nil, line = nil)
        @value = value
        @line = line
      end

      def to_a = [@value, @line]
    end

    class RegexpLit < ::Zr::Record
      FIELDS = %i[source options pinned line].freeze
      attr_accessor :source, :options, :pinned, :line

      def initialize(source = nil, options = nil, pinned = nil, line = nil)
        @source = source
        @options = options
        @pinned = pinned
        @line = line
      end

      def to_a = [@source, @options, @pinned, @line]
    end
    # `"text".freeze`: the one frozen String of that text, through a send
    # of `freeze` where the program redefines it. `shared` is true where
    # a shareable constant or a frozen_string_literal comment holds it:
    # the shared String with no send, as the compiler's own fstring; false
    # is the same for a text outside UTF-8, frozen with no send but not
    # shared.
    class FrozenString < ::Zr::Record
      FIELDS = %i[value line shared].freeze
      attr_accessor :value, :line, :shared

      def initialize(value = nil, line = nil, shared = nil)
        @value = value
        @line = line
        @shared = shared
      end

      def to_a = [@value, @line, @shared]
    end
    # `begin body rescue ... else else_body ensure ensure_body end`. The
    # else arm runs after a body that raised nothing; the ensure arm on
    # every way out. `rescues` are Rescue nodes in order; `else_body` and
    # `ensure_body` may be nil. A `rescue` modifier is a Begin with one
    # clause and no classes.
    class Begin < ::Zr::Record
      FIELDS = %i[body rescues else_body ensure_body line].freeze
      attr_accessor :body, :rescues, :else_body, :ensure_body, :line

      def initialize(body = nil, rescues = nil, else_body = nil, ensure_body = nil, line = nil)
        @body = body
        @rescues = rescues
        @else_body = else_body
        @ensure_body = ensure_body
        @line = line
      end

      def to_a = [@body, @rescues, @else_body, @ensure_body, @line]
    end
    # One clause: the exception classes (none means StandardError; one
    # may be a Splat), the target that takes the exception (`=> e`, an
    # Assign, IvarWrite or Send target with a nil value) or nil, and the
    # handler.
    class Rescue < ::Zr::Record
      FIELDS = %i[classes target body line].freeze
      attr_accessor :classes, :target, :body, :line

      def initialize(classes = nil, target = nil, body = nil, line = nil)
        @classes = classes
        @target = target
        @body = body
        @line = line
      end

      def to_a = [@classes, @target, @body, @line]
    end
    # `retry`: the begin body again, from a rescue clause.
    class Retry < ::Zr::Record
      FIELDS = %i[line].freeze
      attr_accessor :line

      def initialize(line = nil)
        @line = line
      end

      def to_a = [@line]
    end
    # `redo`: the loop body or block body again, without a new test or
    # new arguments.
    class Redo < ::Zr::Record
      FIELDS = %i[line].freeze
      attr_accessor :line

      def initialize(line = nil)
        @line = line
      end

      def to_a = [@line]
    end
  end
end
