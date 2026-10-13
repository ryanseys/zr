# A lazy step packs the values its source yields as ruby 4.1 does
# (rb_enum_values_pack): the block of the lazy's own each gets one value,
# nil for none and an Array for several. Between steps the values stay
# apart, as CRuby's memo keeps them packed with a flag: map, filter_map
# flat_map, take_while and drop_while give their block several values,
# while select, reject, uniq, grep and tap_each give theirs one.
$stdout.sync = true
multi = Enumerator.new { |y| y.yield 1, 2; y.yield; y.yield 3 }
steps = {
  select: ->(l) { l.select { true } }, filter: ->(l) { l.filter { true } }, reject: ->(l) { l.reject { false } },
  take: ->(l) { l.take(5) }, take_while: ->(l) { l.take_while { true } }, drop: ->(l) { l.drop(0) },
  drop_while: ->(l) { l.drop_while { false } }, uniq: ->(l) { l.uniq }, uniq_block: ->(l) { l.uniq { |*a| a } },
  compact: ->(l) { l.compact }, with_index: ->(l) { l.with_index }, each_with_index: ->(l) { l.each_with_index },
  map: ->(l) { l.map { |*a| a } }, filter_map: ->(l) { l.filter_map { |*a| a } }, grep: ->(l) { l.grep(Object) },
  zip: ->(l) { l.zip([9, 9, 9]) }, tap_each: ->(l) { l.tap_each { } }, flat_map: ->(l) { l.flat_map { |*a| [a] } },
  lazy: ->(l) { l }, eager: ->(l) { l.eager }, with_index_block: ->(l) { l.with_index { |*a| } },
  take_zero_after: ->(l) { l.select { true }.map { |*a| a } }
}
steps.each do |name, f|
  got = []
  f.call(multi.lazy).each { |*a| got << a }
  seen = []
  multi.lazy.select { |*a| seen << a; true }.first(3) if name == :select
  p [name, got, seen.empty? ? nil : seen]
end
e = Enumerator.new { |y| y.yield 1, 2; y.yield }
r = ->(l) { got = []; l.each { |*a| got << a }; got }
p r.(Enumerator::Lazy.new([1]) { |y, v| y.yield 1, 2 })
p r.(e.lazy.select { true }.map { |*a| a })
p r.(e.lazy.with_index.map { |*a| a })
p r.(e.lazy.select { true }.select { |*a| p a; true })
p r.(e.lazy.take(5).take(5))
p r.(e.lazy.zip([1,2]).map { |*a| a })
p r.(e.lazy.map { |*a| a }.map { |*a| a })
p r.(e.lazy.filter_map { |a, b| b })
p r.(e.lazy.grep(Object) { |*a| a })
p r.(e.lazy.uniq.map { |*a| a })
p e.lazy.select { true }.to_a, e.lazy.select { true }.first(2), e.lazy.select { true }.force
p e.lazy.select { true }.each_slice(1).to_a
p r.(e.lazy.reject { false }.filter_map { |*a| a })
p r.(e.lazy.take_while { true }.flat_map { |*a| [a] })
p r.(e.lazy.compact.with_index.with_index.map { |*a| a })
p (1..Float::INFINITY).lazy.select(&:even?).map { _1 * 2 }.first(3)
p [[1, 2], [3, 4]].lazy.select { true }.map { |a, b| b }.to_a
e.lazy.take_while { |*a| p [:tw, a]; true }.to_a
e.lazy.drop_while { |*a| p [:dw, a]; true }.to_a
e.lazy.take_while { |v| p [:tw1, v]; true }.to_a
e.lazy.uniq { |*a| p [:u, a] }.to_a
e.lazy.tap_each { |*a| p [:t, a] }.to_a
e.lazy.grep(Object) { |*a| p [:g, a] }.to_a
e.lazy.with_index { |*a| p [:wi, a] }.to_a
