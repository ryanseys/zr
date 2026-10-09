# A major collection gives the heap pages that its sweep left empty back
# to the system, as CRuby's heap_pages_free_unused_pages does, and keeps
# what the live objects need. GC.stat counts them in total_freed_pages,
# and the pages that hold memory in heap_allocated_pages.
# The resident size: from /proc on Linux, whose BusyBox ps has no -p.
def rss_kb
  status = "/proc/self/status"
  return File.foreach(status).find { |line| line.start_with?("VmRSS:") }.split[1].to_i if File.exist?(status)

  `ps -o rss= -p #{$$}`.to_i
end

GC.start
before = GC.stat
big = Array.new(400_000) { |i| [i, i.to_s] }
grown = GC.stat(:heap_allocated_pages)
p grown > before[:heap_allocated_pages]
held = rss_kb
big = nil
GC.start
after = GC.stat
p after[:total_freed_pages] > before[:total_freed_pages]
p after[:heap_allocated_pages] < grown
p after[:total_allocated_pages] >= after[:heap_allocated_pages] + after[:total_freed_pages] - before[:total_freed_pages]
p GC.stat(:total_freed_pages) == after[:total_freed_pages]
p rss_kb < held

# The heap grows again into the pages it gave back.
again = Array.new(400_000) { |i| [i, i.to_s] }
p again.size
p again.last == [399_999, "399999"]

# Process.warmup and GC.compact each count one compaction.
compactions = GC.stat(:compact_count)
GC.compact
Process.warmup
p GC.stat(:compact_count) - compactions
p GC.stat[:compact_count] == GC.stat(:compact_count)
