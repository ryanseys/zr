# An error a core method raises shows the frames of the methods the
# program called and the C methods ruby shows, and none of the helpers
# the runtime keeps for itself: in a block, in sort_by, in Integer(), in
# JSON.parse, in fetch, in eval and in Comparable.
require "json"
def show
  yield
rescue Exception => e
  puts "#{e.class}: #{e.message}"
  puts e.backtrace_locations.map { |l| "#{File.basename(l.path)}:#{l.lineno}:#{l.label}" }
end
show { "a\xffb".force_encoding("UTF-8").grapheme_clusters.map { |c| c.foo } }
show { [3, 1].sort_by { |x| x.zork } }
show { %w[1 x].map { |v| Integer(v) } }
show { JSON.parse("{") }
show { {a: 1}.fetch(:b) }
show { [1].fetch(5) }
show { [1, "a"].sort }
show { [1, 2].each_slice(0) }
show { "abc".unpack("@9") }
show { [1, 2].min_by { |x| raise "in min_by" } }
show { {a: 1}.each { |k, v| raise "in each" } }
show { eval("1 +") }
show { Struct.new(:a).new(1, 2) }
show { "x".encode("NOPE") }
show { Comparable.instance_method(:clamp).bind_call(3, 5, 1) }

