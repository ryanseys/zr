# `RubyVM::AbstractSyntaxTree` over every prism kind zr maps, checked shape
# for shape against ruby.
#
# The taxonomy is parse.y's, not prism's, and the two disagree in ways no
# rule derives: `[]` is its own kind, an absent range endpoint is a NIL NODE,
# a `**rest` is a nil KEY, a writer call is an ATTRASGN, `x += 1` desugars
# while `x ||= 1` does not, and `BEGIN { }` is hoisted out of the statement
# list it was written in. Every span below is a measurement.
#
# `tests/rubyvm_ast.rb` covers the Node/Location SURFACE. This file covers the
# node kinds and their children.
$stderr.reopen(IO::NULL)

def dump(n)
  return "nil" if n.nil?
  return n.inspect unless n.is_a?(RubyVM::AbstractSyntaxTree::Node)
  kids = n.children.map { |c| dump(c) }
  "(#{n.type} [#{n.first_lineno}:#{n.first_column}-#{n.last_lineno}:#{n.last_column}] #{kids.join(' ')})"
end

def show(src)
  puts "#{src.inspect} => #{dump(RubyVM::AbstractSyntaxTree.parse(src))}"
rescue SyntaxError
  puts "#{src.inspect} => SyntaxError"
end

puts "-- literals"
["1", "1.5", "1r", "1i", "?a", ":sym", "nil", "true", "false", "self",
 '"s"', "'s'", '"a" "b"', "`ls`", "/re/", "/x/mix", "%r{x}i", "/x/n",
 "%w[a b]", "%i[a b]", "__FILE__", "__LINE__", "__ENCODING__",
 "1..2", "1...2", "(1..)", "(..2)"].each { |s| show(s) }

