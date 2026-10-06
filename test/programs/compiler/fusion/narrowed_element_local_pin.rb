# The FIRST line pins the tie order of `Array#sort!`: this comparator orders by
# a pair of ranks, so ties are common, and the answer is whatever the C library
# leaves behind. zr sorts through the same `qsort_r` that CRuby's `ruby_qsort`
# calls. That makes the line PER PLATFORM, so there are two goldens:
# `.expected` is macOS, `.linux.expected` linux.
#
# The SECOND line is the main check:
#
# A local bound from a container read (`pair_a = pairs[a]`, where `pairs` is a
# table of int arrays) is narrowed to the element type. The type analysis
# settles, and each method keeps its element types.

def sort_pairs(n)
  rank = Array.new(n) { |i| (n - i) % 3 }
  pairs = Array.new(n) { |i| [rank[i], rank[(i + 1) % n]] }
  sa = Array.new(n) { |i| i }

  sa.sort! do |a, b|
    pair_a = pairs[a]
    pair_b = pairs[b]
    if pair_a[0] != pair_b[0]
      pair_a[0] <=> pair_b[0]
    else
      pair_a[1] <=> pair_b[1]
    end
  end

  ranks = Array.new(n, 0)
  i = 1
  while i < n
    prev_pair = pairs[sa[i - 1]]
    curr_pair = pairs[sa[i]]
    ranks[sa[i]] = ranks[sa[i - 1]] + (prev_pair != curr_pair ? 1 : 0)
    i += 1
  end
  [sa, ranks]
end

p sort_pairs(8)
p sort_pairs(3)
