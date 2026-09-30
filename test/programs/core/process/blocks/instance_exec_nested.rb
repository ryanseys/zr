# Nested instance_exec: each level sets its own self. The inner receiver
# is an outer-scope local that the outer block captures.

class Outer
  def initialize
    @label = 10
  end

  def val
    @label
  end
end

class Inner
  def initialize
    @label = 20
  end

  def val
    @label
  end
end

o = Outer.new
i = Inner.new

# Inner self rebinds to `i`; its `val` reads Inner's ivar.
puts(o.instance_exec { i.instance_exec { val } })   #=> 20

# Outer self rebinds to `o`; the cross-level capture of `i` and the
# rebound-self call compose: 10 + 20.
puts(o.instance_exec { val + i.instance_exec { val } })   #=> 30
puts "done"
