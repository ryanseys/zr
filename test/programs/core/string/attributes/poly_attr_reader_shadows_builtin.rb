# An attr_reader/attr_accessor whose name collides with a builtin
# zero-arg method (value/resume/join -> Thread#value, sum/min/max/first/
# last/sample -> array reductions) must shadow the helper exactly like an
# explicit `def` does.
#
# So `node.value` on an element of an array calls the user reader, and
# arithmetic on the result works.
#
# Reduced from the BART engine, where @roots (an ivar array of Nodes) is
# read in Tree.leaf_stats' `node.value * node.value`.

class Node
  attr_accessor :value, :first
  attr_reader :max
  def initialize
    @value = 1.5
    @first = 7
    @max = "peak"
  end
end

class Forest
  def initialize
    @roots = []          # ivar array of user objects
    @roots << Node.new
  end

  def go
    @roots[0].value * @roots[0].value   # Float reader named like Thread#value
  end

  def head
    n = @roots[0]
    n.first + n.first                   # Int reader named like Array#first
  end

  def peak
    @roots[0].max                       # String reader named like Array#max
  end
end

f = Forest.new
puts f.go        # 2.25
puts f.head      # 14
puts f.peak      # peak

# (The builtin side -- Thread#value through a container when NO user
# class defines the name -- is covered by thread_value_through_container.rb.
# This example does not mix a user `value` reader with Threads in a
# container.)
