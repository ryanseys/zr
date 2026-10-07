# shuffle swaps each slot but the first with a draw at or before it, so
# an Array of one element draws nothing, and a random: object that has no
# public rand is never asked.
class Counting
  attr_reader :draws

  def initialize = @draws = []

  def rand(limit)
    @draws << limit
    limit - 1
  end
end

[[], [1], [1, 2], [1, 2, 3, 4]].each do |a|
  r = Counting.new
  p [a.shuffle(random: r), r.draws]
  r = Counting.new
  b = a.dup
  b.shuffle!(random: r)
  p [b, r.draws]
  r = Counting.new
  p [a.sample(random: r), r.draws]
end

p [1].shuffle(random: 3)
p [].shuffle!(random: Object.new)
p [1].sample(random: 3)
p(begin; [1, 2].shuffle(random: 3); rescue NoMethodError => e; e.message; end)

# A seeded generator gives the same order as before.
p [1, 2, 3, 4, 5].shuffle(random: Random.new(42))
p [1].shuffle(random: Random.new(42))
