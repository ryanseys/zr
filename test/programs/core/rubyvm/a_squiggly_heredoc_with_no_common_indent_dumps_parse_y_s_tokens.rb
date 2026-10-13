# RubyVM::AbstractSyntaxTree of a <<~ heredoc whose lines share no indent:
# parse.y flushes a token at each line while the least indent so far is
# above zero, and joins none of them. A regexp that continues past a
# heredoc's body with a backslash-newline is one token.
def dump(n)
  return n.inspect unless n.is_a?(RubyVM::AbstractSyntaxTree::Node)

  "(#{n.type}@#{n.first_lineno}:#{n.first_column}-#{n.last_lineno}:#{n.last_column} #{n.children.map { dump(_1) }.join(" ")})"
end

sources = [
  "p <<~E\n  x\ny\nE",
  "p <<~E\n  x\n\ny\nE",
  "p <<~E\nx\n\ny\nE",
  "p <<~E\n  x\n\n\ny\nE",
  "p <<~E\n\n  x\ny\nE",
  "p <<~E\n  x\n  \ny\nE",
  "p <<~E\n  x\ny\n\nE",
  "p <<~E\n  x\n\n  y\nE",
  "pp <<-A.gsub(/b\\
a
A
b/, \"\")
",
  "<<~E
  a
\#{1}
  a
E
",
]
sources.each { |src| puts dump(RubyVM::AbstractSyntaxTree.parse(src)) }
