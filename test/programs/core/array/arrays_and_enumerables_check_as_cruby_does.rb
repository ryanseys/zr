# Array and Enumerable: cycle sizes, fill, Range subclasses, warnings,
# grep and $~, to_set and zip, as CRuby gives them.
def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
$VERBOSE = true
$stderr = $stdout
show(1) { [1, 2].cycle(-4).size }
class MyRange < Range; end
show(2) { [1, 2, 3, 4][MyRange.new(1, 2)] }
show(3) { [1, 2, 3].fill }
show(4) { [1, 2, 3].fill("x", 0..1, 1) }
i1 = Object.new; def i1.to_int = 1
i2 = Object.new; def i2.to_int = 2
show(5) { [1, 2, 3].fill("x", i1..i2) }
show(6) { [1, 2, 3].fill("x", "a".."b") }
show(7) { [1, 2].find_index(1) { } }
mm = Object.new
def mm.respond_to_missing?(n, p = false) = n == :to_ary
def mm.method_missing(n, *) = n == :to_ary ? [1, 2] : super
show(8) { [mm].flatten }
show(9) { a = [1]; a << a; b = [1]; b << b; a.hash == b.hash }
show(11) { Array.new { } }
show(12) { [1, 2, 3].slice!(i1..i2) }
show(13) { [1, 2, 3].values_at(i1..i2) }
ta = Object.new; def ta.to_ary = [:a, :b]
show(14) { [1, ta, 2].each_entry.flat_map { |x| x } }
nl = Object.new; def nl.to_ary = nil
show(15) { [nl].each.flat_map { |x| x }.size }
bad = Object.new; def bad.to_ary = 1
show(16) { [bad].each.flat_map { |x| x } }
show(17) { [1].each.map(&proc { |a, b| }).size; arity = nil; [1].each.map { |a, b| arity = :x }; :ok }
show(18) { "z" =~ /z/; %w[a b].grep(/a/); $~[0] }
show(19) { "z" =~ /z/; %w[a b].grep_v(/a/); $~[0] }
show(20) { [:a, "match"].grep(/match/) }
show(21) { [:a, "match"].grep_v(/match/) }
show(22) { [7, 6, 5, 4, 3, 2, 1].each.slice_before { |x| x.even? }.to_a }
show(23) { [7, 6, 5, 4, 3, 2, 1].each.slice_before(Class.new { def ===(x) = x.even? }.new).to_a }
show(24) { [3, 1, 2].each.to_set(Set).class }
show(25) { require "set"; Class.new(Set).then { |c| [1].each.to_set(c).class.superclass } }
conv = Object.new; def conv.to_enum(*) = [9].each; def conv.each = raise("no")
show(26) { [1].zip(conv) }
show(27) { [1].each.zip(conv) }
