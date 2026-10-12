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

puts "-- calls"
["foo", "foo()", "foo 1", "foo(1, 2)", "a.b", "a.b(1)", "a&.b", "a&.b(1)",
 "a[1]", "a[1, 2]", "a[1] = 2", "a.b = 1", "a&.b = 1",
 "foo(*a)", "foo(**h)", "foo(&b)", "foo(1, &b)", "foo(a: 1)", "foo(&:sym)",
 "1 + 2", "-a", "~a", "a <=> b", "a =~ b", "a !~ b", "!a", "-2**2",
 "foo { }", "foo { |x| x }", "foo(1) { }", "a.b { }", "foo { |x, (y, z)| x }",
 "foo { |x, *y, **z, &w| x }", "foo { _1 }", "foo { it }",
 "yield", "yield 1", "super", "super()", "super 1", "super { }",
 "->(x) { x }", "->{ }", "defined?(a)"].each { |s| show(s) }

