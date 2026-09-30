# The same count for Hash, String, Symbol, Float, Range, Struct and
# Data methods, and for the core's own arithmetic and formatting.
SEEN = []
$busy = true
TARGETS = { Integer => %i[== <=> < <= > >= eql? hash + -], String => %i[== <=> eql? hash], Symbol => %i[== <=>], Float => %i[== <=> <] }
TARGETS.each do |klass, ops|
  ops.each do |op|
    original = klass.instance_method(op)
    tag = "#{klass}##{op}"
    klass.define_method(op) do |*args|
      SEEN << tag unless $busy
      original.bind_call(self, *args)
    end
  end
end
$VERBOSE = nil
def run(label)
  SEEN.clear
  $busy = false
  yield
  $busy = true
  puts "#{label}: #{SEEN.tally.sort.map { |tag, n| "#{tag}=#{n}" }.join(' ')}"
end
h = { 1 => 2, 3 => 4 }
s = %w[b a c]
y = %i[b a c]
f = [1.5, 0.5, 2.5]
run("hash value? key") { h.value?(4); h.key(4); h.rassoc(4) }
run("hash eql hash") { h.eql?({ 1 => 2, 3 => 4 }); h.hash }
run("hash str keys") { g = { "a" => 1 }; g["a"]; g.key?("a"); g.merge("b" => 2) }
run("hash compare_by_identity") { g = {}.compare_by_identity; g[1] = 2; g[1] }
run("ary uniq str") { %w[a b a].uniq }
run("ary uniq block") { [1, 2, 3].uniq(&:odd?) }
run("ary <=>") { [1, 2] <=> [1, 3]; s <=> s.dup }
run("ary max str") { s.max; s.min; s.minmax }
run("ary sort floats") { f.sort; f.max }
run("ary include str") { s.include?("c"); s.index("c") }
run("ary include sym") { y.include?(:c); y.index(:c) }
run("ary difference") { [1, 2, 3].difference([2]); [1, 2].union([3]); [1, 2].intersect?([2]) }
run("ary flatten uniq") { [[1, 2], [2, 3]].flatten.uniq }
run("ary sum floats") { f.sum }
run("ary product") { [1, 2].product([3]) }
run("ary bsearch") { [1, 2, 3, 4].bsearch { |x| x >= 3 } }
run("ary fill rotate") { [1, 2, 3].rotate(1); Array.new(3, 0) }
run("enum include") { (1..5).each_slice(2).to_a; (1..3).include?(2); [1, 2].each_entry.include?(2) }
run("enum min_by str") { s.min_by(&:itself); s.max_by(&:itself); s.sort_by(&:itself) }
run("enum sum") { (1..4).sum; (1..4).reduce(1) { _1 * _2 } }
run("enum each_cons") { (1..5).each_cons(2).to_a }
run("enum zip chunk") { [1, 1, 2].chunk_while { _1 == _2 }.to_a }
run("str ==") { "abc" == "abd"; "abc".eql?("abc"); "abc".equal?("abc") }
run("str start end") { "abc".start_with?("a"); "abc".end_with?("c"); "abc".include?("b") }
run("str sub gsub") { "abc".sub("b", "x"); "abc".gsub("b", "x"); "a-b".split("-") }
run("str cmp casecmp") { "a" <=> "b"; "a".casecmp("B"); "a".casecmp?("A") }
run("str succ upto") { "a".upto("c") { } }
run("str hash") { "a".hash; { "x" => 1 }["x"] }
run("sym cmp") { :a <=> :b; :a == :b; y.sort }
run("float cmp") { 1.5 <=> 2.5; 1.5 == 1.5; 1.5 < 2.5; f.min }
run("float round") { 1.25.round(1); 2.5.floor; 3.7.ceil }
run("int pow gcd") { 2**10; 12.gcd(8); 12.lcm(8); 10.digits }
run("int to_s") { 255.to_s(16); 255.to_s(2); Integer("42") }
run("rational") { Rational(1, 2) + Rational(1, 3); 1r == 1 }
run("comparable clamp") { 5.clamp(1, 3); "b".between?("a", "c") }
run("struct eql hash") { S2 = Struct.new(:a) unless defined?(S2); S2.new(1).eql?(S2.new(1)); S2.new(1).hash }
run("data ==") { D2 = Data.define(:a) unless defined?(D2); D2.new(a: 1) == D2.new(a: 1) }
run("range step") { (1..10).step(3).to_a; (1..10).step(3) { } }
run("range each str") { ("a".."c").each { } }
run("range minmax") { (1..5).minmax; (1..5).sum; (1..5).to_a }
run("set ops") { require "set"; (Set[1, 2] | Set[3]); Set[1, 2].subset?(Set[1, 2, 3]) }
run("case str") { case "b" when "a", "b" then 1 end }
run("hash each") { h.each { }; h.sort; h.min_by { _2 } }
run("pack") { [1, 2].pack("C*"); "ab".unpack("C*") }
run("time") { Time.at(0).year; Time.at(0) <=> Time.at(1) }
run("format float") { format("%.2f %05d %x", 1.5, 3, 255) }
run("inspect") { [1, "a", :b, 1.5, nil].inspect; { a: 1 }.to_s }
