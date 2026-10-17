# After an error that parse.y recovers from in place (a jump with nowhere
# to go, a target that cannot be written, a parameter that is no local, a
# setter defined endlessly), Ripper still gives the parser events of the
# whole tree; a bad target is an assign_error inside it, a numbered
# variable's alias an alias_error, and a bad parameter a param_error.
require "ripper"

class Tree < Ripper::SexpBuilderPP
  def on_parse_error(*) = nil
  def compile_error(*) = nil
end

[
  "yield", "yield a", "redo", "retry", "break", "next", "class X; yield; end", "-> { yield }",
  "self = 1", "nil = 1", "$& = 1", "$&, _ = 1", "$& += 1", "$& += cmd 1, 2",
  "def m\n X = 1\nend", "def m\n self::X = 1\nend", "def m\n ::X = 1\nend", "def m\n X, a = 1, 2\nend",
  "def m\n self::X, a = 1, 2\nend", "X = 1", "self::X = 1", "alias $a $1", "def foo(A) end",
  "def foo($a, @b) end", "proc { |A| }", "def foo=() = 42", "def foo.bar=() = 42 rescue 0",
  "proc{|&b;y|}", "def b(*); c(*) end", "def b; c(*) end", "def req(a, a) end"
].each do |source|
  p [source, Tree.new(source).parse]
end
