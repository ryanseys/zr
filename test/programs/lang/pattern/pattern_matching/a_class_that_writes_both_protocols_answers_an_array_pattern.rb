# frozen_string_literal: true

# A class with the two protocols answers both an array and a hash
# pattern. `**rest` hands `deconstruct_keys` nil, which is what tells it
# the pattern will take everything.
class Pair
  def initialize(a, b) = (@a, @b = a, b)
  def deconstruct = [@a, @b]
  def deconstruct_keys(keys) = { a: @a, b: @b, keys: keys }
end

pair = Pair.new("x", "y")

case pair
in [one, two] then p [:arr, one, two]
end

case pair
in { a:, keys: } then p [:keys, a, keys]
end

case pair
in { **all } then p [:all, all]
end

