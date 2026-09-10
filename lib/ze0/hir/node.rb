# frozen_string_literal: true

module Ze0
  # The high-level IR: a tree of Ruby-level nodes, desugared and
  # name-resolved, that every lowering reads instead of Prism. One class
  # per kind; `line` is where the node starts; `locals` lists every local
  # of a scope, parameters first.
  module Hir
    # `frozen` holds when the file's magic comment freezes string literals.
    # `units` are the files a require or load reaches, each a toplevel
    # of its own, in the order they were first named. `warnings` are the
    # parse-time warnings ruby prints for the file, printed when it runs.
    Program = Struct.new(:file, :locals, :body, :frozen, :units, :warnings)
    Unit = Struct.new(:file, :locals, :body, :frozen, :warnings, :internal)
    # `require`, `require_relative` or `load` of a literal name: `path`
    # is the file it resolved to and `unit` that file's index, or both
    # nil when no file answers.
    Require = Struct.new(:kind, :feature, :path, :unit, :line)

    # A form this runtime does not answer, held until the program runs
    # it. Reaching it stops the program by name; never reaching it costs
    # nothing.
    Stop = Struct.new(:what, :line)
    # `autoload :Name, "feature"` on `recv` (nil for self): the file is
    # `path`, unit `unit`; it runs when the constant is first read.
    Autoload = Struct.new(:recv, :name, :feature, :path, :unit, :line)
    # A statement list; its value is the last statement's.
    Seq = Struct.new(:stmts, :line)
    # A method call. `recv` is nil for an implicit self; `vcall` marks a
    # bare identifier, which is a NameError when nothing answers; `opt`
    # marks the operator syntax `recv[i]`, `recv[i] = v` and `recv << v`,
    # which CRuby runs without a frame on its builtin receivers. An
    # argument may be a Splat; `kwargs` is a HashLit passed as keywords,
    # or nil; `block` is a Block literal, a BlockPass, or nil.
    Send = Struct.new(:recv, :name, :args, :line, :vcall, :opt, :block, :kwargs, :safe, :write)
    # A value the lowering has already put in record slot `index`: the
    # lowering's own node, for a receiver or argument evaluated once.
    Slot = Struct.new(:index, :line)
    # `recv[args] op= value` and `recv.name op= value`, the receiver and
    # arguments evaluated once; `op` is an operator, or :or / :and.
    IndexOpAssign = Struct.new(:recv, :args, :op, :value, :line)
    # `safe` is `recv&.name op= value`: nil, with nothing else run,
    # when the receiver is nil.
    AttrOpAssign = Struct.new(:recv, :name, :op, :value, :line, :safe)
    # `*value` among arguments or elements.
    Splat = Struct.new(:value, :line)
    # `**value` among a hash literal's pairs: the key, with a nil value.
    HashSplat = Struct.new(:value, :line)
    # `&value`: the block a call passes on.
    BlockPass = Struct.new(:value, :line)
    # A block literal: its parameters, every local of its scope
    # (parameters first), and its body.
    Block = Struct.new(:params, :locals, :body, :line)
    # `-> (params) { body }`: a Block that is a lambda from the start.
    Lambda = Struct.new(:block, :line)
    # The one parameter shape: `required` and `post` are names,
    # `optional` and `keywords` are `[name, default]` pairs (a keyword
    # with no default is required), `rest`, `kwrest` and `block` are a
    # name or nil; a block's `|a, |` has the rest `:implicit`.
    Params = Struct.new(:required, :optional, :rest, :post, :keywords, :kwrest, :block) do
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
      # destructuring parameter with no name.
      def rows
        positional = ->(p) { p.is_a?(MultiTarget) ? [:req] : [:req, p] }
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
    Yield = Struct.new(:args, :line, :kwargs)
    # `super(args)`; `block` as a Send's. `ZSuper` is the bare `super`,
    # passing the method's own parameters on as they stand.
    Super = Struct.new(:args, :kwargs, :block, :line)
    ZSuper = Struct.new(:block, :line)
    Break = Struct.new(:value, :line)
    Next = Struct.new(:value, :line)
    # An Integer, String, Symbol, nil, true or false.
    Literal = Struct.new(:value, :line)
    SelfRef = Struct.new(:line)
    # `def name(params) body end`; its value is the name. `params` is a
    # Params; `receiver` is the expression of a singleton def
    # (`def self.x`, `def obj.x`), or nil.
    Def = Struct.new(:name, :params, :locals, :body, :line, :receiver, :evals)
    # `depth` counts block scopes up to the one that holds the local.
    Local = Struct.new(:name, :depth, :line)
    Assign = Struct.new(:name, :depth, :value, :line)
    # `a, (b, *c), *d, e = value`; its value is the right-hand side's.
    MultiAssign = Struct.new(:target, :value, :line)
    # The targets before the rest, the rest (a target, `:implicit` for a
    # bare `*`, or nil) and the targets after it. A target is an Assign
    # or IvarWrite with a nil value, a Send with the value to append
    # (`h[k]`, `o.attr`), or a nested MultiTarget. As a block parameter,
    # a MultiTarget stands among the required names.
    MultiTarget = Struct.new(:lefts, :rest, :rights, :line, :whole) do
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
    If = Struct.new(:cond, :yes, :no, :line)
    # `body_first` is a `begin ... end while cond`: the body runs once
    # before the first test.
    While = Struct.new(:cond, :body, :line, :body_first)
    Return = Struct.new(:value, :line)
    # `a && b`, `a || b`, `!a`: on truthiness, short circuit.
    And = Struct.new(:left, :right, :line)
    Or = Struct.new(:left, :right, :line)
    Not = Struct.new(:value, :line)
    # `class Name < superclass; body; end`. `scope` is nil for a bare
    # name, `:top` for `::Name`, else the expression before `::`.
    ClassDef = Struct.new(:scope, :name, :superclass, :locals, :body, :line)
    ModuleDef = Struct.new(:scope, :name, :locals, :body, :line)
    # `class << target; body; end`: the body runs with the singleton
    # class as self and as the definee.
    SingletonClassDef = Struct.new(:target, :locals, :body, :line)
    ConstRead = Struct.new(:scope, :name, :line)
    ConstWrite = Struct.new(:scope, :name, :value, :line)
    IvarRead = Struct.new(:name, :line)
    GvarRead = Struct.new(:name, :line)
    GvarWrite = Struct.new(:name, :value, :line)
    CvarRead = Struct.new(:name, :line)
    CvarWrite = Struct.new(:name, :value, :line)
    # `Name ||= value`: set only when unset or falsy.
    ConstOrWrite = Struct.new(:scope, :name, :value, :line)
    # `alias new old`.
    Alias = Struct.new(:new_name, :old_name, :line)
    # `alias $new $old`: one global under two names.
    GvarAlias = Struct.new(:new_name, :old_name, :line)
    # `undef name, ...`.
    Undef = Struct.new(:names, :line)

    # `alias :"#{a}" :"#{b}"` and `undef :"#{a}"`: the names are values.
    AliasValue = Struct.new(:new_name, :old_name, :line)

    UndefValue = Struct.new(:names, :line)
    # `defined?(...)`: `kind` names the form (:local, :ivar, :gvar,
    # :cvar, :const, :method, :yield, :super, :self, :nil, :true, :false,
    # :assignment, :expression); `target` is the name, the ConstRead, or
    # the Send the form asks about.
    Defined = Struct.new(:kind, :target, :line)
    # `case subject; when a, b then body; ... else else_body end`. Each
    # clause is `[values, body]`; a nil subject tests each value itself.
    Case = Struct.new(:subject, :clauses, :else_body, :line)
    IvarWrite = Struct.new(:name, :value, :line)
    ArrayLit = Struct.new(:elements, :line)
    # `{k => v, ...}`: `pairs` is a flat list, key then value.
    HashLit = Struct.new(:pairs, :line)
    # `low..high` / `low...high`; a missing bound is nil.
    RangeLit = Struct.new(:low, :high, :exclusive, :line)
    # `"a#{b}c"`: literal and expression parts in order.
    Interp = Struct.new(:parts, :line)
    # A regexp literal: its source and option bits; one object per site.
    # `/#{x}/o`: the interpolated regexp its site keeps after the first run.
    RegexpOnce = Struct.new(:value, :line)

    RegexpLit = Struct.new(:source, :options, :pinned, :line)
    # `"text".freeze`: the one frozen String of that text.
    FrozenString = Struct.new(:value, :line)
    # `begin body rescue ... else else_body ensure ensure_body end`. The
    # else arm runs after a body that raised nothing; the ensure arm on
    # every way out. `rescues` are Rescue nodes in order; `else_body` and
    # `ensure_body` may be nil. A `rescue` modifier is a Begin with one
    # clause and no classes.
    Begin = Struct.new(:body, :rescues, :else_body, :ensure_body, :line)
    # One clause: the exception classes (none means StandardError; one
    # may be a Splat), the target that takes the exception (`=> e`, an
    # Assign, IvarWrite or Send target with a nil value) or nil, and the
    # handler.
    Rescue = Struct.new(:classes, :target, :body, :line)
    # `retry`: the begin body again, from a rescue clause.
    Retry = Struct.new(:line)
    # `redo`: the loop body or block body again, without a new test or
    # new arguments.
    Redo = Struct.new(:line)
  end
end
