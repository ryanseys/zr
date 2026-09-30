# A local assigned `Class.new` inside a top-level method body resolves
# as an instance_exec receiver. Inside the block, bare calls go to that
# receiver's class. This works in a top-level method, as in a class body.

class Tally
  def initialize
    @sum = 0
  end

  def add(n)
    @sum = @sum + n
  end

  def sum
    @sum
  end
end

def accumulate
  t = Tally.new
  t.instance_exec { add(3); add(4); sum }
end

puts accumulate     #=> 7
puts "done"
