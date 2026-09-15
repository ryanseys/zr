# A thread that only computes hands the turn on wherever it loops: at a
# `next` or `redo` that jumps back before the loop's end, and inside the
# runtime's own iterators, whose bodies have no back edge of compiled
# Ruby at all. The worker gets its turn, and a kill reaches each spinner.

Thread.report_on_exception = false
spinners = [
  Thread.new { while true; next; end },
  Thread.new { while true; redo; end },
  Thread.new { 10_000_000_000.times { } },
  Thread.new { 0.upto(10_000_000_000) { } },
  Thread.new { 10_000_000_000.downto(0) { } },
  Thread.new { a = [1] * 1_000_000; while true; a.each { }; a.map { }; a.select { }; end },
  Thread.new { h = (1..100_000).to_h { |i| [i, i] }; while true; h.each { }; end },
]
worker = Thread.new { 21 + 21 }
p worker.value
spinners.each(&:kill).each(&:join)
p spinners.map(&:alive?)

__END__
42
[false, false, false, false, false, false, false]
