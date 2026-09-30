# A blockless `each_slice`/`each_cons`/`each_with_index` over an ENDLESS Range
# answers, because the Enumerator it returns re-invokes the block form, and
# those roll a buffer through the source instead of materializing it first.
#
# The trailing comments record what Ruby answers.
r = ((1..5).cycle(2).to_a rescue $!.class)
p r

r = ((1..5).each_entry.to_a rescue $!.class); p r        # Ruby: [1, 2, 3, 4, 5]
r = ((1..).each_slice(2).first(2) rescue $!.class); p r  # Ruby: [[1, 2], [3, 4]]

r = ((1..).each_cons(2).first(2) rescue $!.class); p r        # Ruby: [[1, 2], [2, 3]]
r = ((1..).each_with_index.first(2) rescue $!.class); p r     # Ruby: [[1, 0], [2, 1]]

p((1..3).each_with_index.to_a)   # => [[1, 0], [2, 1], [3, 2]]

o = []; (1..3).cycle(2) { |x| o << x }; p o    # => [1, 2, 3, 1, 2, 3]
o = []; (1..3).each_entry { |x| o << x }; p o   # => [1, 2, 3]

r = ((1..).each_slice(3).first(1) rescue $!.class); p r
r = ((5..).each_with_index.first(3) rescue $!.class); p r
r = ((1..).lazy.with_index(10).first(2) rescue $!.class); p r
r = ([1, 2, 3, 4].each_cons(2).to_a rescue $!.class); p r
