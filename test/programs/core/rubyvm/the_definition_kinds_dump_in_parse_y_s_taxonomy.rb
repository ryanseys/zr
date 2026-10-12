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

puts "-- definitions"
["def m; end", "def m(); end", "def m(a); end", "def m(a = 1); end",
 "def m(*a); end", "def m(*); end", "def m(a:); end", "def m(a: 1); end",
 "def m(**k); end", "def m(**); end", "def m(**nil); end", "def m(&b); end",
 "def m(&); end", "def m(a, *b, c); end", "def m(a, (b, c)); end",
 "def m(a, b = 1, *c, d, e:, f: 2, **g, &h); end",
 "def self.m; end", "def m = 1", "def m; 1; end", "def m(); 1; end",
 "def m; rescue; end", "def m(a, ...); n(...); end", "def m(...) = n(...)",
 "class Foo; end", "class Foo < Bar; end", "class Foo::Bar; end",
 "class << self; end", "module M; end", "module M::N; end",
 "alias a b", "alias $a $b", "undef a", "undef a, b"].each { |s| show(s) }

