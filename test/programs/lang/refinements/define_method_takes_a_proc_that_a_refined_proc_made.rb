# define_method refuses the Proc that Proc#refined returns, also after a
# second #refined, but takes a Proc or a block that the body of a refined
# Proc made: that one inherits the refinements, and the method it defines
# runs with them. A nested refined Proc adds its own to those it inherits.
def try(l) = (p [l, yield]) rescue p([l, $!.class, $!.message])
module RS; refine(String) { def shout = upcase + "!" }; end
module RI; refine(Integer) { def doubled = self * 2 }; end
try(:nested) { -> { inner = ->(s, n) { [s.shout, n.doubled] }; inner.refined(RS).call("hi", 3) }.refined(RI).call }
try(:dm_nested) { c = -> { Class.new { define_method(:m, ->(n) { n.doubled }) } }.refined(RI).call; c.new.m(4) rescue $!.class }
try(:dm_direct) { Class.new { define_method(:m, ->(s) { s }.refined(RS)) } }
try(:dm_chain) { Class.new { define_method(:m, ->(s) { s }.refined(RS).refined(RI)) } }
try(:dm_block) { -> { Class.new { define_method(:m) { 5.doubled } } }.refined(RI).call.new.m rescue $!.class }
try(:dm_outside) { c = -> { Class.new { define_method(:m, ->(n) { n.doubled }) } }.refined(RI).call; 3.respond_to?(:doubled) }
try(:dm_twice) { c = -> { Class.new { define_method(:m) { |s| [s.shout, s.size.doubled] } } }.refined(RI, RS).call; c.new.m("ab") }
