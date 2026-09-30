# Class hierarchy of user classes: .superclass, .ancestors, and
# `<` / `<=`. Modules, dynamic is_a? and case-when on Class are
# in other examples; this one stays on user-class inheritance.

class A
end

class B < A
end

class C < B
end

# .superclass goes up one step.
puts B.superclass.to_s  # => A
puts C.superclass.to_s  # => B
# A's superclass is Object per CRuby.
puts A.superclass == Object ? "A-root-ok" : "A-root-bad"

# .ancestors returns an Array of Class and Module values. Iterate
# and concatenate the names.
def names_of(arr)
  out = ""
  arr.each do |klass|
    out += "," unless out.length == 0
    out += klass.to_s
  end
  out
end

puts names_of(C.ancestors)  # => "C,B,A,Object,Kernel,BasicObject"
puts names_of(A.ancestors)  # => "A,Object,Kernel,BasicObject"

# `<` / `<=` -- proper / non-proper subclass.
puts (C < A) ? "C<A" : "C!<A"
puts (C <= A) ? "C<=A" : "C!<=A"
puts (A < A) ? "A<A" : "A!<A"
puts (A <= A) ? "A<=A" : "A!<=A"
puts (A < C) ? "A<C" : "A!<C"
