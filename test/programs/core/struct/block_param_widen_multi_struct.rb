# A block on a receiver whose class is not known, for a name that builtin
# Enumerable also has (`each`). The receiver can be a builtin container at run
# time, so the block params can hold any value. Every Struct defines `each`, and
# this file has two Structs, so more than one user class has the name too.

module Probe
  Disallowed = Struct.new(:term)
  Finding = Struct.new(:path, :term)

  def self.check(scope)
    scope.keys.each { |a| [1].each { |b| Finding.new(a, a) } }
  end
end

f = Probe::Finding.new("a.rb", "Order")
puts "#{f.path} #{f.term}"

# and the method actually called (the example does not print its return
# value; it checks that the call works and the members stay right)
Probe.check({ "x" => 1 })
p Probe::Finding.new("b.rb", "Term").path

# one Struct
module Solo
  Only = Struct.new(:v)

  def self.walk(scope)
    scope.keys.each { |a| [1].each { |b| Only.new(a) } }
  end
end
p Solo::Only.new("s").v
Solo.walk({ "y" => 2 })

# three, to show it is not about the count
module Trio
  A = Struct.new(:x)
  B = Struct.new(:y)
  C = Struct.new(:z)

  def self.walk(scope)
    scope.each { |a| [1].each { |b| C.new(a) } }
  end
end
p Trio::C.new("t").z
Trio.walk(["u"])

# a name no user class defines still types its param from the receiver: this is
# what over-widening broke (a Range element is an Integer, not a poly)
total = 0
(1..3).each { |x| total += x }
p total
p (1..3).map { |x| x * 2 }
p [1, 2, 3].each_cons(2).map { |pair| pair[0] + pair[1] }
