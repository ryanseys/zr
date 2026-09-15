# A live set far larger than the mark stack's initial size (1024 cells):
# the walk has to stay iterative rather than recursing per object.
heap = []
20_000.times { |i| heap << [i, i * 2] }
GC.start
p heap.size
p heap[0]
p heap[19_999]
p heap.sum { |pair| pair[1] } == 20_000 * 19_999

__END__
20000
[0, 0]
[19999, 39998]
true
