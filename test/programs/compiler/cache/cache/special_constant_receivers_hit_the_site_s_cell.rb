# One site, receivers of five classes in turn: nil, true, false, a
# symbol and a String. The site finds each class itself and its
# cells answer; a method defined or redefined after the site ran
# is what the next send reaches.
def describe(x) = x.tag

class NilClass; def tag = "nil"; end
class TrueClass; def tag = "true"; end
class FalseClass; def tag = "false"; end
class Symbol; def tag = "sym #{self}"; end
class String; def tag = "str #{self}"; end

inputs = [nil, true, false, :a, "s", nil, :b, false]
p inputs.map { |x| describe(x) }
p inputs.map { |x| describe(x) }

class NilClass; def tag = "nil again"; end
class Symbol; def tag = "sym again"; end
p inputs.map { |x| describe(x) }

# Predicates on a special constant, ten thousand times at one site.
n = 0
20_000.times { |i| n += 1 if (i.even? ? nil : :s).nil? }
p n
p [nil, true, false, :x].map(&:frozen?)
p [nil, false, :y].map { |x| x.respond_to?(:tag) }
