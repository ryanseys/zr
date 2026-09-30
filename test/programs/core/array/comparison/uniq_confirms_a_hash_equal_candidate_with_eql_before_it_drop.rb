# `Array#uniq` confirms hash-equal candidates with `eql?`.
#
# Two objects with colliding hashes are one key only when `eql?` says so.
# `a_user_hash_that_collides.rb` checks the rest, including Hash lookup.
c = Struct.new(:v) do
  def hash = 0
  def eql?(o) = v == o.v
end
p [c.new(1), c.new(1), c.new(2)].uniq.length
p [c.new(1), c.new(2)].uniq { |x| x }.length
