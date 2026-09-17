p 5.clamp(1, 3), 5.clamp(..3), 5.clamp(7..), 5.clamp(4..6), "b".clamp("c", "d"), 2.5.clamp(1, 2), (5.clamp(1...3) rescue $!.message), (5.clamp(3, 1) rescue $!.message), 5.clamp(nil, 4), 5.clamp(6, nil)
p 6.allbits?(2), 6.allbits?(3), 6.anybits?(1), 6.anybits?(3), 6.nobits?(1), 6.nobits?(2), 15.truncate(-1), -15.truncate(-1), 15.truncate(1), 7.ceildiv(2), -7.ceildiv(2), 7.ceildiv(-2), 0.ceildiv(3)
p "a".upto("e").to_a, "a".upto("e", true).to_a, "9".upto("11").to_a, "az".upto("bc").to_a, "a".upto("a").to_a, "b".upto("a").to_a, ("a".upto("c") { |s| print s }), "1.9".upto("2.1").to_a
puts
p "ab".codepoints, "".codepoints, "a-b-c".partition("-"), "abc".partition("x"), "a-b-c".rpartition("-"), "abc".rpartition("x"), "abc".sum, "".sum, "abc".sum(4), "hello".byteslice(1, 2), "hello".byteslice(1), "hello".byteslice(1..3), "hello".byteslice(9), "hello".byteslice(-2, 5), "hello".byteslice(5, 1), "hello".byteslice(6, 1)
p "aabbcc".tr_s("ab", "xy"), "aabbcc".tr_s("a-c", "x"), "hello".tr_s("l", "r"), "hello".tr_s("el", "*"), "a\nb\t\"c\\".dump, "a\e".dump, "\x00\x7f".dump, "abc".dump
p "ff".hex, "0xff".hex, "-0x1A".hex, "zz".hex, "12abc".hex, "".hex, "0x".hex, "1_0".hex, "17".oct, "0x1f".oct, "0b101".oct, "-017".oct, "8".oct, "0o17".oct, "1_7".oct, "".oct, " 17".oct
p "a1b2a3".scan("a"), "aaa".scan("aa"), "abc".scan("x"), "".scan("a"), "abab".scan("ab") { |m| print m }, "aXbXc".scan("X").size
puts
p [1, 2, 3].combination(2).to_a, [1, 2, 3].combination(0).to_a, [1, 2, 3].combination(4).to_a, [1, 2, 3].combination(3).to_a, [1, 2].combination(1).size, [1, 2, 3].combination(2).class, ([1, 2].combination(1) { |c| print c.inspect }).class
puts
p [1, 2, 3].permutation.to_a, [1, 2, 3].permutation(2).to_a, [1, 2].permutation(0).to_a, [1, 2].permutation(3).to_a, [1, 2, 3].permutation(2).size, [1, 2].permutation.size, [].permutation.to_a
p [[1, 2], [3, 4]].rassoc(4), [[1, 2], [3, 4]].rassoc(9), [1, [2, 3]].rassoc(3), [[1, 2]].rassoc(1)
p [1, 3, 5, 7].bsearch { |x| x >= 4 }, [1, 3, 5, 7].bsearch { |x| x >= 9 }, [1, 3, 5, 7].bsearch { |x| 5 <=> x }, [1, 3, 5, 7].bsearch { |x| 4 <=> x }, [1, 3, 5, 7].bsearch_index { |x| x >= 4 }, [1, 3, 5, 7].bsearch_index { |x| x >= 9 }, [].bsearch { true }, [1, 2].bsearch.class, ([1].bsearch { "x" } rescue $!.message), [1, 3, 5].bsearch { |x| x >= 1 }, [1, 3, 5].bsearch { |x| 0 }
p [1, 2, 2, 3].intersection([2, 3, 4], [3, 2]), [1, 2].intersection, [1, 1, 2].union([2, 3], [4]), [1].union, [1, 2, 2, 3].difference([2], [3]), [1, 2].difference, [1, 2].intersect?([2, 3]), [1, 2].intersect?([3]), [].intersect?([]), [1, 2].intersection([2.0]), [1].union([1.0])
p [3, 1, 2].max(2), [3, 1, 2].min(2), [3, 1, 2].max(0), [3, 1, 2].max(5), [3, 1, 2].max(2) { |a, b| b <=> a }, [3, 1, 2].min(1) { |a, b| b <=> a }, [].max(2), ([1].max(-1) rescue $!.message), %w[bb a ccc].max(2), %w[bb a ccc].min(2), [3, 1, 2].each.max(2), (1..5).max(2), (1..5).min(2), { a: 2, b: 1 }.max(1), [1, 2, 3].max_by(2) { |x| -x }, [1, 2, 3].min_by(2) { |x| -x }
a = [1, 2, 3, 4]
p a.rotate!, a, a.rotate!(2), a, a.rotate!(-1), a.rotate!(0), [].rotate!, [1].rotate!(5)
p({ a: 1, b: [2, 3] }.flatten, { a: 1, b: [2, [3]] }.flatten(2), { a: [1] }.flatten(0), {}.flatten, { a: 1 }.rehash, { a: 1 }.rehash.class)
h = {}
k = [1]
h[k] = :v
k << 2
p h.rehash[k], h[[1, 2]]
p (1..5).overlap?(3..7), (1..5).overlap?(6..7), (1...5).overlap?(5..7), (1..5).overlap?(5..7), (1..).overlap?(..0), (..1).overlap?(1..), (1..5).overlap?(3...3), (3...3).overlap?(1..5), ("a".."c").overlap?("b".."d"), ((1..5).overlap?(1) rescue $!.message), (5..1).overlap?(1..5)
p (1..10).bsearch { |x| x >= 4 }, (1..10).bsearch { |x| x >= 11 }, (1...4).bsearch { |x| x >= 4 }, (1..10).bsearch { |x| 7 <=> x }, (0..100).bsearch { |x| x * x >= 50 }, (1..).bsearch { |x| x > 1000 }, (1..10).bsearch.class, ((1.0..2.0).bsearch { |x| x >= 1.5 } rescue $!.class), (1..0).bsearch { true }
p (1.0..2.0).step(0.5).to_a, (1.0...2.0).step(0.5).to_a, (1..2).step(0.5).to_a, (1.0..2.0).step(0.5).class, (1.0..2.0).step(0.5), (1.0..2.0).step(0.5).size, (0.0..1.0).step(0.1).to_a, (1..2).step(0.5) { |x| print x, " " }, (1.0..2.0).step(1).to_a, (1.0..).step(0.5).first(3), 1.0.step(2.0, 0.5).to_a, 1.step(2, 0.5).to_a, 1.0.step(by: 0.5, to: 2.0).to_a, 1.step(by: 2, to: 6).to_a, 1.step(6, 2).to_a, 10.step(1, -3).to_a, 1.0.step(2.0, 0.5).size, 1.step(2, 0.5).class, ((1..2).step(0) rescue $!.message), ((1.0..2.0).step(-0.5).to_a)
puts
p putc("a"), putc(66), putc("xyz"), (putc(nil) rescue $!.class)
puts
p pp, pp(1), pp(1, 2), pp({ a: 1 }), Hash([]), Hash(nil), Hash({ a: 1 }), (Hash([[1, 2]]) rescue $!.message), (Hash(1) rescue $!.message), (Hash([1]) rescue $!.message)
p "d".display, 1.display, nil.display
puts
p 1.public_method(:+).call(2), (1.public_method(:puts) rescue $!.message), 1.public_method(:+).class, method(:exit!).arity, method(:exit!).owner
o = Object.new
def o.x = 1
p o.singleton_method(:x).call, o.singleton_method(:x).class, o.singleton_method(:x).owner == o.singleton_class, (o.singleton_method(:y) rescue $!.class), (1.singleton_method(:x) rescue $!.class), o.singleton_class.attached_object.equal?(o), (Integer.attached_object rescue $!.message), Integer.singleton_class.attached_object
m = Module.new
p m.name, m.set_temporary_name("fake_name").name, m.name, m.to_s, m.set_temporary_name(nil).name, (m.set_temporary_name("Bad") rescue $!.message), (Object.set_temporary_name("x") rescue $!.message), (m.set_temporary_name("") rescue $!.message)
p Class.new { attr :a; attr :b, :c }.new.tap { |x| x.instance_variable_set(:@a, 1) }.a, Class.new { attr :a }.instance_methods(false)
class Alias
  def orig = 1
  alias other orig
  alias_method :third, :orig
end
p Alias.new.method(:other).original_name, Alias.new.method(:other).name, Alias.new.method(:third).original_name, Alias.new.method(:orig).original_name, Alias.instance_method(:other).original_name, 1.method(:+).original_name, Alias.new.method(:other).inspect
p (1 !~ 2 rescue $!.class), ("a" !~ "a" rescue $!.class), (nil !~ 1 rescue $!.class), (:a !~ 1 rescue $!.class)
p 1.0.next_float, 1.0.prev_float, 0.0.next_float, 0.0.prev_float, (-0.0).next_float, Float::MAX.next_float, Float::INFINITY.next_float, Float::NAN.next_float.nan?, 1.0.next_float.prev_float, (1.0.next_float - 1.0), Float::MIN.prev_float, (-Float::MAX).prev_float, 100.0.next_float, 1e300.next_float
at_exit { puts "not printed" }
exit!(3)
