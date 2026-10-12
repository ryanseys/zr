# transform_keys! converts a given mapping, nil too, before it checks
# that the Hash is not frozen. With no mapping and no block it gives an
# enumerator.
def show(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

show("nil") { { a: 1 }.transform_keys!(nil) }
show("nil with a block") { { a: 1 }.transform_keys!(nil) { _1 } }
show("frozen, nil") { { a: 1 }.freeze.transform_keys!(nil) }
show("frozen, 1") { { a: 1 }.freeze.transform_keys!(1) }
show("frozen, a Hash") { { a: 1 }.freeze.transform_keys!({}) }
show("frozen, a block") { { a: 1 }.freeze.transform_keys!(&:to_s) }
show("enumerator") { e = { a: 1, b: 2 }.transform_keys!; [e.size, e.each(&:to_s)] }
show("mapping and block") { { a: 1, b: 2 }.transform_keys!({ a: :z }) { |k| k.to_s } }
show("mapping only") { { a: 1, b: 2 }.transform_keys!({ a: :b, b: :a }) }
show("block") { { a: 1 }.transform_keys!(&:to_s) }
show("to_hash") { o = Object.new; def o.to_hash = { a: :q }; { a: 1 }.transform_keys!(o) }
show("too many") { { a: 1 }.transform_keys!({}, {}) }
