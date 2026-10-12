# merge, merge! and update take each argument in turn, as rb_hash_update
# does in C: a bad one raises from the method's own frame, with no frame
# of Array#each.
def labels
  p yield
rescue StandardError => e
  p [e.class, e.message, e.backtrace_locations.map(&:label).take_while { |l| !l.start_with?("block") }]
end

labels { {}.merge(1) }
labels { { a: 1 }.merge({ b: 2 }, nil) }
labels { {}.merge!(1) }
labels { {}.update({}, :a) }
labels { { a: 1 }.freeze.update({}) }
labels { { a: 1 }.merge({ b: 2 }, { c: 3 }) }
labels { { a: 1 }.merge({ a: 2 }, { a: 3 }) { |_k, old, new| old + new } }
labels { { a: 1 }.update({ a: 2 }, { a: 3 }) { |_k, old, new| old * new } }
labels { { a: 1 }.merge }
labels { h = { a: 1 }; h.update(h, h) }
labels { o = Object.new; def o.to_hash = { z: 1 }; { a: 1 }.merge(o) }
labels { { a: 1 }.merge({ a: 2 }) { raise "in the block" } }
