# frozen_string_literal: true

module Ze0
  # The high-level IR: a tree of Ruby-level nodes, desugared and
  # name-resolved, that every lowering reads instead of Prism. One class
  # per kind; `line` is where the node starts; `locals` lists every local
  # of a scope, parameters first.
  module Hir
    Program = Struct.new(:file, :locals, :body)
    # A statement list; its value is the last statement's.
    Seq = Struct.new(:stmts, :line)
    # A method call. `recv` is nil for an implicit self; `vcall` marks a
    # bare identifier, which is a NameError when nothing answers; `index`
    # marks `recv[args]` and `recv[args] = value` syntax.
    Send = Struct.new(:recv, :name, :args, :line, :vcall, :index)
    # An Integer, String, Symbol, nil, true or false.
    Literal = Struct.new(:value, :line)
    SelfRef = Struct.new(:line)
    # `def name(params) body end`; its value is the name.
    Def = Struct.new(:name, :params, :locals, :body, :line)
    Local = Struct.new(:name, :line)
    Assign = Struct.new(:name, :value, :line)
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
    ConstRead = Struct.new(:scope, :name, :line)
    ConstWrite = Struct.new(:scope, :name, :value, :line)
    IvarRead = Struct.new(:name, :line)
    IvarWrite = Struct.new(:name, :value, :line)
    ArrayLit = Struct.new(:elements, :line)
  end
end
