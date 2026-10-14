# `RubyVM::AbstractSyntaxTree` over every prism kind zr maps, checked shape
# for shape against ruby.
#
# The taxonomy is parse.y's, not prism's, and the two disagree in ways no
# rule derives: `[]` is its own kind, an absent range endpoint is a NIL NODE,
# a `**rest` is a nil KEY, a writer call is an ATTRASGN, `x += 1` desugars
# while `x ||= 1` does not, and `BEGIN { }` is hoisted out of the statement
# list it was written in. Every span below is a measurement.
#
# The node and location tests of this directory cover their methods.
# This file covers the node kinds and their children.
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

puts "-- control flow"
["if a then 1 else 2 end", "if a; end", "if a; elsif b; else; end",
 "unless a; else; end", "1 if a", "a ? 1 : 2",
 "while a; end", "while a do b end", "until a; end",
 "begin; a; end while b", "for i in a; end", "for a, b in c; end",
 "case a; when 1 then 2; else 3; end", "case a; when *b then 1; end",
 "break", "break 1", "next", "redo", "retry", "return 1",
 "begin; a; rescue => e; b; else; c; ensure; d; end",
 "begin; a; rescue A, B => e; end", "a rescue b",
 "a and b", "a or b", "not a", "a && b", "a || b"].each { |s| show(s) }

