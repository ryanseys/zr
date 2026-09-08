# frozen_string_literal: true

module Ze0
  # The high-level IR: a tree of Ruby-level nodes, desugared and
  # name-resolved, that every lowering reads instead of Prism. One class
  # per kind; `line` is where the node starts.
  module Hir
    Program = Struct.new(:file, :body)
    # A statement list; its value is the last statement's.
    Seq = Struct.new(:stmts, :line)
    # A method call. `recv` is nil for an implicit self; `vcall` marks a
    # bare identifier, which is a NameError when nothing answers.
    Send = Struct.new(:recv, :name, :args, :line, :vcall)
    # An Integer, String, Symbol, nil, true or false.
    Literal = Struct.new(:value, :line)
    SelfRef = Struct.new(:line)
  end
end
