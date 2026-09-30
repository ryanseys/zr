# A builtin instance method called with a count CRuby rejects raises
# CRuby's own ArgumentError, with its message.
#
# What this file was FILED for is fixed, and it crashed the whole
# process: `Enumerable#first` with two arguments hit an internal
# assumption about the argument count that the CALLER actually controls.
# Ten such cases are ordinary raises now.
#
# Two more rows were silently LENIENT rather than loud: `Array#first` read
# `args[0]` out of a `*args` it never counted, and `Range#first`/`#last`
# spelled their bound `0..1` where CRuby's message spells it `1`.

def check
  yield
rescue => e
  p [e.class, e.message]
end

# missing required argument (compile-time SIGSEGV before the arity guard)
check { (1..3).cover? }
check { (1..3).include? }
# an operator spelled as a method call with its operand missing
check { :a.<=> }
check { 1.+() }
# too few for an exact multi-argument method
s = +"x"
check { s.insert(1) }
h = {a: 1}
check { h.store(1) }
# too many for a zero-argument method
check { :a.to_s(9) }
check { "x".succ(1) }
# too many for a bounded optional range
check { "x".chomp("a", "b") }
check { [1, 2].first(1, 2) }
check { (1..2).first(1, 2) }
# variadic minimum
a = [1]
check { a.insert }
# the valid shapes still answer
p (1..2).first
p "x".chomp
p [1, 2].first(1)
# a block changes several counts: the bare-call spec must not fire
p [1].fill { 9 }
