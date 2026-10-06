# Integer#times sends `<` and `succ` once a program redefines either, for
# a Bignum as for a Fixnum.
called = []
Integer.class_eval do
  alias_method :old_succ, :succ
  define_method(:succ) { called << :succ; old_succ }
  alias_method :old_lt, :<
  define_method(:<) { |x| called << :lt; old_lt(x) }
end

p 2.times { |i| i }
p called
called.clear
p((2**65).times { |i| break i if i == 1 })
p called
