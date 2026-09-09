# frozen_string_literal: true

module Ze0
  # The high-level IR: a tree of Ruby-level nodes, desugared and
  # name-resolved, that every lowering reads instead of Prism. One class
  # per kind; `line` is where the node starts; `locals` lists every local
  # of a scope, parameters first.
  module Hir
    # `frozen` holds when the file's magic comment freezes string literals.
    Program = Struct.new(:file, :locals, :body, :frozen)
    # A statement list; its value is the last statement's.
    Seq = Struct.new(:stmts, :line)
    # A method call. `recv` is nil for an implicit self; `vcall` marks a
    # bare identifier, which is a NameError when nothing answers; `opt`
    # marks the operator syntax `recv[i]`, `recv[i] = v` and `recv << v`,
    # which CRuby runs without a frame on its builtin receivers. An
    # argument may be a Splat; `kwargs` is a HashLit passed as keywords,
    # or nil; `block` is a Block literal, a BlockPass, or nil.
    Send = Struct.new(:recv, :name, :args, :line, :vcall, :opt, :block, :kwargs, :safe)
    # A value the lowering has already put in record slot `index`: the
    # lowering's own node, for a receiver or argument evaluated once.
    Slot = Struct.new(:index, :line)
    # `recv[args] op= value` and `recv.name op= value`, the receiver and
    # arguments evaluated once; `op` is an operator, or :or / :and.
    IndexOpAssign = Struct.new(:recv, :args, :op, :value, :line)
    AttrOpAssign = Struct.new(:recv, :name, :op, :value, :line)
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

      # Whether a lone Array argument spreads over the parameters.
      def spread?
        positional > 1 || (positional == 1 && !rest.nil?)
      end

      # Only required parameters: the exact arity a dispatcher may check.
      def plain?
        optional.empty? && rest.nil? && post.empty? && keywords.empty? && kwrest.nil?
      end

      def names
        positionals = (required + post).flat_map { |r| r.is_a?(MultiTarget) ? r.names : [r] }
        positionals + optional.map(&:first) + [rest].compact + keywords.map(&:first) + [kwrest, block].compact - [:implicit]
      end
    end
    Yield = Struct.new(:args, :line)
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
    Def = Struct.new(:name, :params, :locals, :body, :line, :receiver)
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
    MultiTarget = Struct.new(:lefts, :rest, :rights, :line) do
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
    While = Struct.new(:cond, :body, :line)
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
    # `"a#{b}c"`: literal and expression parts in order.
    Interp = Struct.new(:parts, :line)
    # `begin body rescue ... else else_body ensure ensure_body end`. The
    # else arm runs after a body that raised nothing; the ensure arm on
    # every way out. `rescues` are Rescue nodes in order; `else_body` and
    # `ensure_body` may be nil. A `rescue` modifier is a Begin with one
    # clause and no classes.
    Begin = Struct.new(:body, :rescues, :else_body, :ensure_body, :line)
    # One clause: the exception classes (none means StandardError), the
    # local that takes the exception (`=> e`, as a name and depth) or
    # nil, and the handler.
    Rescue = Struct.new(:classes, :name, :depth, :body, :line)
    # `retry`: the begin body again, from a rescue clause.
    Retry = Struct.new(:line)
  end
end
