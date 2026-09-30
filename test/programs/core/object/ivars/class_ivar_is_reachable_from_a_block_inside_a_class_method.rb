# The block captures `self` as the class itself, so the ivar
# resolves through the dynamic lookup path rather than the static
# class-id path -- the two must agree on the same storage.

class Blk
  @vals = []
  def self.collect
    [1, 2, 3].each { |i| @vals << i * 10 }
    @vals
  end
end
p Blk.collect
