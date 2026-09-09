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
    # bare identifier, which is a NameError when nothing answers; `index`
    # marks the operator syntax `recv[i]`, `recv[i] = v` and `recv << v`,
    # which CRuby runs without a frame on its builtin receivers.
    Send = Struct.new(:recv, :name, :args, :line, :vcall, :opt, :block)
    # A block literal: its parameters, every local of its scope
    # (parameters first), and its body.
    Block = Struct.new(:params, :locals, :body, :line)
    Yield = Struct.new(:args, :line)
    Break = Struct.new(:value, :line)
    Next = Struct.new(:value, :line)
    # An Integer, String, Symbol, nil, true or false.
    Literal = Struct.new(:value, :line)
    SelfRef = Struct.new(:line)
    # `def name(params) body end`; its value is the name. `receiver` is
    # the expression of a singleton def (`def self.x`, `def obj.x`), or nil.
    Def = Struct.new(:name, :params, :locals, :body, :line, :receiver)
    # `depth` counts block scopes up to the one that holds the local.
    Local = Struct.new(:name, :depth, :line)
    Assign = Struct.new(:name, :depth, :value, :line)
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
