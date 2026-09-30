# Modules as values and in the ancestors of a class.
#
# Coverage:
#   - module constant in value position (Greeting / Comparable
#     lookalike) is a Module value.
#   - <class>.ancestors weaves included modules in include-reverse
#     order followed by the parent chain.
#   - <class> <= <module> checks the ancestors.
#   - <class> == <module> never holds.

module Greeting
  def hello
    "hello"
  end
end

module Politeness
  def please
    "please"
  end
end

class Base
end

class Polite < Base
  include Greeting
  include Politeness
end

# Module name as value.
m = Greeting
puts m.to_s          # => Greeting

# Ancestors include the modules in include-reverse order.
def names_of(arr)
  out = ""
  arr.each do |klass|
    out += "," unless out.length == 0
    out += klass.to_s
  end
  out
end

puts names_of(Polite.ancestors)
# => Polite,Politeness,Greeting,Base,Object,Kernel,BasicObject

# <= check on a module via the ancestors table.
puts (Polite <= Greeting) ? "polite<=Greeting" : "polite!<=Greeting"
puts (Polite <= Politeness) ? "polite<=Politeness" : "polite!<=Politeness"
puts (Base <= Greeting) ? "base<=Greeting" : "base!<=Greeting"

# Equality: a class is never == its included module.
puts (Polite == Greeting) ? "eq" : "neq"
