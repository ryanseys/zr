# Enumerable#each_with_index calls the receiver's each, so an error out of
# its block shows the each's frame under each_with_index, as ruby's
# rb_block_call does, for an Array as for a Hash or a Range.
def show
  yield
rescue => e
  puts e.backtrace.map { |l| l.sub(/^.*?:\d+:in /, "") }.inspect
end
show { [1].each_with_index { raise "x" } }
show { [1].each_with_index.to_a.each { raise "x" } }
show { {a: 1}.each_with_index { raise "x" } }
show { (1..1).each_with_index { raise "x" } }
show { [1].each_with_index.each { raise "x" } }
show { [1].each_slice(1) { raise "x" } }
show { [1].map.with_index { raise "x" } }
