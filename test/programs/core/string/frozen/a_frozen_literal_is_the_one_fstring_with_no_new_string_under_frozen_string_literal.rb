# frozen_string_literal: true
# A frozen literal (`"text".freeze`, `-"text"`) is the one fstring of its
# text, made with no new String once the fstring exists, in a file of any
# script encoding. A redefined String#freeze or String#-@ then runs.
def strings = ObjectSpace.count_objects[:T_STRING]

def allocations
  GC.disable
  before = strings
  yield
  strings - before
ensure
  GC.enable
end

h = { "abc" => 1 }
k = "abc".freeze
p allocations { 5.times { h["abc".freeze] } }
p allocations { 5.times { "abc".freeze } }
p allocations { 5.times { -"abc" } }
p allocations { 5.times { h[-"abc"] } }
p "abc".freeze.equal?(-"abc"), "abc".freeze.equal?(k), k.equal?(h.keys.first)
p "abc".freeze.encoding, (-"abc").encoding, (-"abc").frozen?
p (-"abc").equal?(-"abc".dup), (-"ab#{"c"}").equal?(-"abc")
p "abc".freeze.equal?("abc".dup.force_encoding("UTF-8").freeze)

class String
  def -@ = "minus(#{self})"
end
p(-"abc")
class String
  def freeze = "frozen(#{self})"
end
p "abc".freeze
