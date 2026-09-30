# Implicit-self direct call inside a class method:
#   def configure
#     instance_exec(10) { |n| add(n) }   # no explicit receiver
#   end
#
# CRuby resolves this to `self.instance_exec(10) { |n| add(n) }`.

class Builder
  def initialize
    @s = 0
  end
  def add(n)
    @s = @s + n
  end
  def total
    @s
  end

  # Implicit-self direct call -- no explicit receiver. Resolves
  # to self.instance_exec(...).
  def configure
    instance_exec(10) { |n| add(n) }
    instance_exec(20) { |n| add(n) }
    instance_eval { add(12) }   # sibling: instance_eval implicit-self too
  end
end

b = Builder.new
b2 = Builder.new
b.configure
puts b.total   # 42

puts "done"
