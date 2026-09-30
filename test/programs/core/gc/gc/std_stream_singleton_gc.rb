# A standard stream stored into a GC-scanned slot.
#
# The three standard streams are singletons in static storage, not GC
# allocations. An assignment such as `$stderr = $stdout` stores one into a
# global that the collector marks. The collector must treat the stream as a
# stream, and the streams must still work after each collection.

$stderr = $stdout
GC.start
puts "stderr assigned"

$stdout = $stderr
GC.start
puts "stdout assigned"

# a collection with real garbage to sweep, so the mark walk is not trivial
1000.times { |i| s = "row #{i}" ; s.upcase }
GC.start
puts "after churn"

# the streams still work as streams
$stderr.puts "written"
$stdout.flush
p $stderr == $stdout

# a stream held in an ordinary local and an array survives a collection too:
# the same pointer, now reachable from a scanned container
out = $stdout
box = [$stdout, $stderr]
GC.start
out.puts "through a local"
p box.length
