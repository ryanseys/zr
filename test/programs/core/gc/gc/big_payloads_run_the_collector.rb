# The bytes Strings, Arrays and Hashes hold outside their cells count
# toward a collection: a program that keeps few cells but makes large
# payloads collects, so its memory stays bounded, and GC.stat reports
# the payload held and the count that runs the collector.
before = GC.stat[:count]
keep = nil
200.times { keep = "x" * 8_000_000 }
p GC.stat[:count] - before > 5, keep.size
before = GC.stat[:count]
a = nil
100.times { a = Array.new(2_000_000, 1) }
p GC.stat[:count] - before > 3, a.size
held = GC.stat[:malloc_increase_bytes]
limit = GC.stat[:malloc_increase_bytes_limit]
p held.is_a?(Integer), held >= 0, limit >= 16 * 1024 * 1024, held < limit
keep = a = nil
GC.start
p GC.stat[:malloc_increase_bytes] < 64 * 1024 * 1024

