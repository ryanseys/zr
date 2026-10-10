h = { a: 1, "b" => 2, 3 => :three, nil => 0 }
p h
p h[:a], h["b"], h[3], h[nil], h[:zzz]
h[:c] = 4
h["b"] = 20
p h.size, h.length, h.empty?, {}.empty?
p h.key?(:a), h.key?(:q), h.has_key?("b"), h.include?(3), h.member?(nil)
p h.keys, h.values
h.each { |k, v| puts "#{k.inspect}=#{v.inspect}" }
h.each_pair { |pair| p pair }
p h.delete(:a), h.delete(:nope), h.keys
p h.fetch("b")
begin
  h.fetch(:missing)
rescue KeyError => e
  p e
end
p h.fetch(:missing, "default")
p h.fetch(:missing) { |k| "block #{k}" }
s = "key"
h2 = { s => 1 }
p h2.keys.first.frozen?, s.frozen?, h2.keys.first.equal?(s)
h2["key"] = 2
p h2
e = {}
p e, e[:x], e.to_a
p h == { "b" => 20, 3 => :three, nil => 0, :c => 4 }, h == {}, {} == {}
p h.to_a
p({ 1 => 2 }.inspect, { "s" => [1, { x: nil }] })
h3 = { [1, 2] => "array key" }
p h3[[1, 2]], h3[[1, 3]]
p h.map { |k, v| [k, v] }
count = 0
h.each { |k, v| count += 1 }
p count
p h.to_h.equal?(h), Hash.new, Hash.new(5)[:x]
d = Hash.new { |hash, key| hash[key] = key.to_s * 2 }
p d[:ab], d
p h.any?, {}.any?, h.select { |k, v| v == 20 }, h.reject { |k, v| v == 20 }.size
p h.merge({ z: 26 }), h.key(20), h.invert
p h.first, h.count, h.sum { |k, v| 1 }
p h.transform_values { |v| v.to_s }, h.filter_map { |k, v| k if v == 20 }
p h.find { |k, v| v == 4 }, h.is_a?(Enumerable), Hash.include?(Enumerable), h.include?(3)
h.each_with_index { |pair, i| p [pair, i] }
h.each_key { |k| p k }
p h.value?(20), h.value?(99), h.all? { |k, v| v }, h.none? { |k, v| v == 0 }
begin
  Hash.new(1, 2)
rescue ArgumentError => e
  p e
end
begin
  h.fetch
rescue ArgumentError => e
  p e
  puts e.backtrace
end
{ q: 1 }.map { |k, v| raise "in map" } rescue puts $!.backtrace
{ q: 1 }.each { |k, v| raise "in each" } rescue puts $!.backtrace
class Foo
  include Enumerable
  def each
    yield 1
    yield 2
    yield 3
  end
end
p Foo.new.map { |x| x * 2 }
p Foo.new.select { |x| x > 1 }, Foo.new.to_a, Foo.new.first, Foo.new.include?(2), Foo.new.count, Foo.new.inject(10) { |a, x| a + x }
p Foo.new.is_a?(Enumerable), Foo.superclass, Foo.new.class
module M; def m = :m; end
module N; include M; def n = :n; end
class Bar; include N; end
p Bar.new.m, Bar.new.n, Bar.new.is_a?(M), Bar.include?(M), Bar.superclass
begin
  Bar.include(Foo)
rescue TypeError => e
  p e
end
