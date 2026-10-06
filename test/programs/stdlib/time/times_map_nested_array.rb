require "time"  # Time#iso8601 is require-gated stdlib (matches CRuby)


def t_times_map_nested_array
  # `N.times.map { block-returns-array }` answers an Array of
  # Arrays, and each inner Array keeps its elements.

  a = 2.times.map { (0..2).map { |i| i + 1 } }
  p a

  b = 3.times.map { [10, 20, 30] }
  p b
end
t_times_map_nested_array
