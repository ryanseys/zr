def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end

t(:object_space_garbage) { ObjectSpace.garbage_collect.class }
t(:obj_id_reuse) { Object.new.object_id.class }
t(:hash_order) { h = {}; 20.times { |i| h[i.to_s] = i }; 10.times { |i| h.delete(i.to_s) }; h.keys.first(3) }
t(:hash_compare_by_id) { h = {}.compare_by_identity; a = "a"; h[a] = 1; h["a".dup] = 2; h.size }
t(:hash_default_proc) { h = Hash.new { |hh, k| hh[k] = k * 2 }; [h[3], h.to_a, h.default_proc.arity] }
t(:hash_mutation_iter) { h = {a: 1}; h.each { h[:b] = 2 } }
t(:array_mutation_iter) { a = [1, 2, 3]; a.each { a.delete_at(0) }; a }
t(:recursive_inspect) { a = [1]; a << a; h = {}; h[:s] = h; [a.inspect, h.inspect, a.hash == a.hash] }
t(:recursive_eq) { a = [1]; a << a; b = [1]; b << b; a == b }
t(:sort_stability) { (1..20).map { [_1 % 3, _1] }.sort_by(&:first).map(&:last) }
t(:sort_block_break) { [3, 1, 2].sort { break :broke } }
t(:min_max) { [[3, 1, 2].minmax, %w[aa b ccc].max_by(&:size), [1, 2, 3].sum(0.0), [0.1] * 10 == [0.1] * 10, ([0.1] * 10).sum, [1e100, 1.0, -1e100].sum] }
t(:pack_misc) { [[1, 2].pack("s>l<"), [1.5].pack("e"), ["abc"].pack("m0"), (["a"].pack("U*") rescue $!.class), [65, 0x263a].pack("U*"), "\x01\x02".unpack("n"), [1].pack("w"), ["x"].pack("Z*"), [1, 2].pack("C2x2"), "abc".unpack("a2 @0 a1")] }
t(:range) { [(1..10).step(3).to_a, ("a".."e").each_slice(2).to_a, (1...10).size, (1..).first(2), (..5).include?(3), (1..10) === 5.5, ("a".."z").cover?("bb"), (1.0..2.0).step(0.5).map { _1 }, Range.new(1, 5, true).minmax, (1..0).sum, ((1..3) % 2).class] }
t(:comparable) { 5.clamp(1, 3) }
t(:enumerator_lazy) { (1..Float::INFINITY).lazy.map { _1 * 2 }.with_index.select { |x, i| i.even? }.first(2) }
t(:enumerator_product) { Enumerator.product([1, 2], [3, 4]).to_a }
t(:enumerator_chain) { ([1].each + [2]).to_a }
t(:enumerator_yielder) { Enumerator.new { |y| y.yield 1, 2; y << 3 }.to_a }
t(:enumerator_size) { [1, 2, 3].each_slice(2).size }
t(:each_entry) { [[1, 2], [3]].each_entry.to_a }
t(:zip) { [1, 2].zip([3], [4, 5, 6]) }
t(:flat_map) { [[1, [2]], [3]].flat_map { _1 } }
t(:chunk) { [1, 2, 4, 5, 7].chunk_while { |a, b| b == a + 1 }.to_a }
t(:tally) { %w[a b a].tally }
t(:each_cons) { (1..4).each_cons(2).to_a }
t(:array_ops) { a = [5, 3, 1]; [a.bsearch { _1 >= 3 }, a.sort.bsearch_index { _1 >= 3 }, a.pack("C*"), a.rotate(-1), a.combination(2).count, a.permutation.first, a.product([0]).size, (a.transpose rescue $!.class), a.each_slice(2).map(&:sum), a.dig(0), a.filter_map { _1 if _1 > 1 }, a.intersect?([1]), [nil, 1, false].compact, a.values_at(0, 5, -1), a.fill(0, 1), a.inspect] }
t(:array_pack_neg) { [-1].pack("Q") }
t(:string_to_sym_weird) { "foo=".to_sym.inspect }
t(:kernel_misc) { [Integer("0b11", 0), Float("1_000.5"), String(nil), Array(nil), Array(a: 1), Hash([[1, 2]]), Rational("0.75"), format("%3$s %1$s", "a", "b", "c")] }
t(:frozen_literals) { [:a.frozen?, 1.frozen?, nil.frozen?, "a#{1}".frozen?, //.frozen?, (1..2).frozen?, [].frozen?] }
t(:object_methods) { [1.frozen?, Object.new.singleton_methods, 5.instance_variables, nil.to_a, nil & true, true ^ true, 1.itself, 3.then { _1 + 1 }, Object.new.tap { }.class] }
t(:dup_special) { [1.dup, nil.dup, :a.clone, (1.clone(freeze: false) rescue $!.class)] }
t(:respond_to_ops) { [1.respond_to?(:+), Object.new.respond_to?(:puts), Object.new.respond_to?(:puts, true)] }
t(:spaceship) { [1 <=> "a", nil <=> nil, [1, 2] <=> [1, 3], "a" <=> 1] }
t(:catch_obj) { catch { |tag| throw tag, 7 } }
t(:ensure_order) { r = []; begin; begin; r << 1; return_val = 1; ensure; r << 2; end; ensure; r << 3; end; r }
t(:exit_in_ensure) { begin; exit 0; ensure; puts "ensure ran"; end if false; :skipped }
t(:loop_stopiteration) { e = [1].each; loop { e.next }; :done }
t(:loop_result) { e = [1].each; loop { e.next } }
t(:obj_to_s) { Object.new.to_s =~ /\A#<Object:0x\h{16}>\z/ ? :ok : :bad }
