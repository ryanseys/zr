# Where ruby's C sends `each` by name (rb_block_call), a program's
# `each` runs, once for each walk.
$calls = 0
module CountEach
  def each(*, &) = ($calls += 1; super)
end
[Array, Hash, Range].each { |klass| klass.prepend(CountEach) }
checks = {
  "each_slice" => -> { [1, 2, 3].each_slice(2).to_a },
  "inject" => -> { [1, 2].inject(:+) },
  "zip hash" => -> { [1, 2].zip({ a: 1 }) },
  "lazy map" => -> { [1, 2].lazy.map { _1 * 2 }.to_a },
  "lazy flat_map" => -> { [1, 2].lazy.flat_map { [_1, _1] }.first(3) },
  "range first" => -> { (1..5).first(2); (1..5).first(0) },
  "chain" => -> { [1].chain([2]).to_a },
  "enumerator +" => -> { ([1].each + [2]).to_a },
  "hash map" => -> { { a: 1 }.map { _1 } },
  "set merge" => -> { Set[1].merge({ c: 1 }) },
  "sort_by!" => -> { [2, 1].sort_by! { _1 } },
}
checks.each do |name, check|
  before = $calls
  check.call
  $stdout.write("#{name}: #{$calls - before}\n")
end
