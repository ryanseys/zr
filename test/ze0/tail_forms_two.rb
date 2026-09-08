# frozen_string_literal: true

# More forms that needed no machinery of their own.

# `a..b` written where a condition goes is ruby's flip-flop: a latch that
# turns ON where `a` is true and OFF where `b` is, answering true for every
# test in between. The state outlives the statement, so it lives in the
# runtime's own table and each site owns one.
inclusive = []
(1..8).each { |i| inclusive << i if (i == 3)..(i == 5) }
p inclusive

# The two ends can be the same test: `..` asks the right operand at once, so
# it ends where it started; `...` waits for the next test.
one = []
many = []
(1..6).each do |i|
  one << i if (i == 3)..(i == 3)
  many << i if (i == 3)...(i == 3)
end
p one
p many

# Two sites keep separate latches, and one that never turns off runs on.
a = []
b = []
(1..6).each do |i|
  a << i if (i == 2)..(i == 4)
  b << i if (i == 3)..(i == 99)
end
p a, b

# A bare `k: v` tail is ONE Hash element inside an array literal: there is
# no keyword channel to put it in.
p [1, { b: 2 }, c: 3, d: 4]

# `Outer::Inner = v` where the scope is a class this program declares hands
# the runtime an owner id; a nested path, or a scope only the run time can
# name, is read as a VALUE and the constant is set on it.
module A
  module B
    LEVEL = 1
  end
end
A::B::LEVEL = 42
p A::B::LEVEL

module Registry; end
def stock(m)
  m::LIST ||= []
  m::LIST << :entry
end
stock(Registry)
stock(Registry)
p Registry::LIST

# `module_function :name` of a method an `include` supplied: which ancestor
# carries it is the run time's own question.
module Greet
  def hello(who) = "hi #{who}"
end
module Util
  include Greet
  module_function :hello
end
p Util.hello("x")
p Util.private_instance_methods(false).include?(:hello)

# An omitted end never fires: a beginless flip-flop never turns on and an
# endless one never turns off.
beginless = []
endless = []
(1..5).each do |i|
  beginless << i if ..(i == 3)
  endless << i if (i == 2)..
end
p beginless, endless

# `h[*keys] = v`: how many index arguments there are is a run-time number,
# so the setter takes one Array. The answer is still V.
h = {}
keys = [:k]
p(h[*keys] = 9)
p h

# Names only the run time builds are the runtime's own visibility verb.
HIDDEN = %i[one two]
class Both
  def one = 1
  def two = 2
  def three = 3
  private(*HIDDEN)
end
p Both.private_instance_methods(false).sort
p Both.public_instance_methods(false).sort
__END__
[3, 4, 5]
[3]
[3, 4, 5, 6]
[2, 3, 4]
[3, 4, 5, 6]
[1, {b: 2}, {c: 3, d: 4}]
42
[:entry, :entry]
"hi x"
true
[]
[2, 3, 4, 5]
9
{k: 9}
[:one, :two]
[:three]
#@ stderr
ze0/tail_forms_two.rb:45: warning: already initialized constant A::B::LEVEL
ze0/tail_forms_two.rb:42: warning: previous definition of LEVEL was here
