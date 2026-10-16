# Symbol#[] and #slice run rb_str_aref in C, so an error shows only
# 'Symbol#[]' or 'Symbol#slice', with no frame of String's. The other
# methods that read the name call String's own C functions too, so a
# program's redefinition or prepend of a String method changes none of
# them, nor does a program's String#to_sym.
def label
  yield
rescue StandardError => e
  p [e.class, e.message, e.backtrace_locations.first.label]
end

label { :abc[nil] }
label { :abc.slice(1, 2, 3) }
label { :abc[] }
label { :abc["a", "b"] }
label { :abc.upcase(:nope) }
label { :abc.start_with?(1) }
label { :abc.casecmp?(:ABC).foo }

p [:abc[1], :abc[0, 2], :abc[/b./], :abc.slice(-1), :abc[5]]
p [:abc.upcase, :ABC.downcase, :abc.capitalize, :aBc.swapcase, :az.succ, :az.next]
p [:abc.start_with?("a"), :abc.end_with?("c", "x"), :abc.casecmp(:ABC), :abc.casecmp?(:ABC)]

module Loud
  def upcase(*) = "LOUD"
  def [](*) = "loud"
end

class String
  prepend Loud
  def to_sym = :hijacked
  def succ = "hijacked"
  def start_with?(*) = :hijacked
  def casecmp?(*) = :hijacked
end

p [:abc.upcase, :abc[0], :abc.succ, :aB.swapcase, :abc.start_with?("a"), :abc.casecmp?(:ABC)]
p ["abc".upcase, "abc"[0], "abc".succ, "abc".to_sym]
