# An ivar first assigned inside an instance_exec / instance_eval block
# becomes an ivar of the receiver. No method here references @w or @s --
# the only writes are inside the blocks. Box has a subclass.
class Box
  def initialize
    @v = 1
  end
end

class BoxPlus < Box
end

b = BoxPlus.new

# int ivar first assigned (and read) inside the block
puts b.instance_exec { @w = 7; @w + 1 }

# string ivar assigned in one block, read back in a later block
b.instance_eval { @s = "hi" }
puts b.instance_exec { @s }

# the statically-declared ivar still resolves
puts b.instance_exec { @v }
