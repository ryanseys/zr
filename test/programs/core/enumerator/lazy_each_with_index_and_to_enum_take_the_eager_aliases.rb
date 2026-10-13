# ruby 4.1 adds Enumerator::Lazy#each_with_index, with_index(0) under its
# own name (Bug #21142), and its private _enumerable_each_with_index.
# lazy.to_enum(name) names the eager alias of a method that Lazy
# overrides, so it iterates; the enumerator that a core method returns
# keeps the name, as rb_enumeratorize does, and yields nothing.
lz = (1..3).lazy
e = lz.to_enum(:with_index, 10)
p e, e.to_a
e = lz.enum_for(:map)
p e, e.to_a, e.each { |x| x * 2 }
e = lz.to_enum(:each_with_index)
p e, e.to_a
e = lz.to_enum("select")
p e, e.to_a
p lz.send(:_enumerable_with_index, 10), lz.send(:_enumerable_with_index, 10).to_a
p lz.each_with_index, lz.each_with_index.to_a, lz.each_with_index.size, lz.each_with_index { |x, i| p [x, i] }.to_a
p lz.each_with_index.map { |x, i| x * i }.to_a, (1..).lazy.each_with_index.select { |x, i| i.even? }.first(2)
p lz.each_with_index.with_index(5).to_a, lz.with_index.each_with_index.to_a
p lz.each_slice(2), lz.each_slice(2).to_a
p lz.each_with_object([]), lz.each_with_object([]).to_a
p Enumerator::Lazy.private_instance_methods(false).sort
p lz.method(:each_with_index).arity, lz.method(:_enumerable_each_with_index).owner
p lz.send(:_enumerable_map), lz.send(:_enumerable_map).to_a
