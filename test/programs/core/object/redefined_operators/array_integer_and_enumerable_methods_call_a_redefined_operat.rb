# The core's own methods call a redefined operator exactly as often as
# ruby's C does: through rb_equal, rb_eql and OPTIMIZED_CMP where it
# dispatches, and never where it compares natively.
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
a = [3, 1, 2, 5, 4]
s = %w[b a c]
y = %i[b a c]
run("ary ==") { [1, 2, 3] == [1, 2, 3] }
run("ary include") { a.include?(4) }
run("ary index") { a.index(5); a.rindex(1) }
run("ary delete") { a.dup.delete(2) }
run("ary count") { a.count(2) }
run("ary uniq") { [1, 1, 2].uniq }
run("ary -") { a - [1, 2] }
run("ary &") { a & [1, 2] }
run("ary sort") { a.sort }
run("ary sort str") { s.sort }
run("ary sort sym") { y.sort }
run("ary min max") { a.min; a.max; a.minmax }
run("ary sum") { a.sum }
run("ary assoc") { [[1, 2], [3, 4]].assoc(3); [[1, 2], [3, 4]].rassoc(4) }
run("ary hash") { a.hash }
run("ary eql") { a.eql?(a.dup) }
run("hash lookup") { h = { 1 => 2, "x" => 3, :y => 4 }; h[1]; h["x"]; h[:y] }
run("hash ==") { { 1 => 2 } == { 1 => 2 } }
run("hash value?") { { 1 => 2 }.value?(2); { 1 => 2 }.key(2) }
run("range each") { (1..5).each { } }
run("range include") { (1..5).include?(3); (1..5) === 3; (1..5).cover?(3) }
run("range ==") { (1..2) == (1..2) }
run("int times") { 5.times { } }
run("int upto") { 1.upto(5) { }; 5.downto(1) { } }
run("int step") { 1.step(10, 3) { } }
run("int between") { 3.between?(1, 5); 3.clamp(1, 5) }
run("str ==") { "a" == "a"; "a".eql?("a") }
run("str cmp") { "a" <=> "b" }
run("str case") { case "b" when "a" then 1 when "b" then 2 end }
run("int case") { case 3 when 1 then 1 when 3 then 2 end }
run("sym case") { case :b when :a then 1 when :b then 2 end }
run("struct ==") { S = Struct.new(:a) unless defined?(S); S.new(1) == S.new(1) }
run("sort_by") { a.sort_by { -_1 } }
run("min_by") { a.min_by { _1 } }
run("group_by") { a.group_by(&:odd?) }
run("tally") { [1, 1, 2].tally }
run("each_with_index") { a.each_with_index { } }
run("inject") { a.inject(:+) }
run("zip flatten") { a.zip(a).flatten }
run("str split") { "a,b,c".split(",") }
run("format") { format("%d %s", 1, "a") }
run("set") { require "set"; Set[1, 2, 3].include?(2) }
