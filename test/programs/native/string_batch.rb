# Pipe has no wasm form.
p "a\nb\n".lines("b"), "a--b--c".lines("--"), "a\n\nb\n\n\nc".lines(""), "abc".each_line("b").to_a, "a\nb".lines(chomp: true), "a--b".lines("--", chomp: true), "a\r\nb\r\n".lines(chomp: true), "a\nb".lines(nil), "".lines, "a\n\n\n\nb".lines(""), "a\n\nb".lines("", chomp: true), "abc".lines("c"), "x\ny\n".each_line { |l| print l.inspect, " " }
puts
p ("a".."e").step(2).to_a, ("a".."e").step(2).class, ("a".."e").step(1).to_a, ("aa".."ad").step(3).to_a, (("a".."e").step(0) rescue $!.message), ("a".."c").step(2) { |s| print s }, ("a".."e") % 2
puts
p "abc".bytesplice(1, 1, "XY"), "abc".bytesplice(1..2, "Q"), "hello".bytesplice(0, 2, "XYZ", 1, 2), "abc".bytesplice(3, 0, "d"), ("abc".bytesplice(4, 0, "d") rescue $!.message), ("héllo".bytesplice(1, 1, "x") rescue $!.message), ("abc".bytesplice(0, -1, "x") rescue $!.message)
s = +"hello"; p s.tr!("l", "L"), s, s.tr!("z", "L"), s.tr_s!("L", "x"), s
s = +"az"; p s.succ!, s, s.next!, s.equal?(s.succ!)
p "ab".each_codepoint.to_a, "héllo".each_codepoint.to_a, "ab".each_codepoint { |c| print c, " " }
puts
p "x".dedup.frozen?, "x".dedup.equal?("x".dedup), "abc".delete_prefix!("a"), "abc".delete_prefix!("z"), "abc".delete_suffix!("c"), "abc".delete_suffix!("z"), String.try_convert(1), String.try_convert("a"), Hash.try_convert([]), Hash.try_convert({a: 1}), Array.try_convert([1]), Array.try_convert("x"), IO::NULL, [1, 2, 3].slice(1, 2), [1, 2, 3].slice(0), [1, 2, 3].slice(1..)
class Strish; def to_str = "s"; end
class Badish; def to_str = 1; end
p String.try_convert(Strish.new), (String.try_convert(Badish.new) rescue $!.message)
p "\"a\\nb\"".undump, "\"\\u00e9\"".undump, "\"\\x00\\xff\"".undump.bytes, "\"tab\\there\"".undump, "\"q\\\"q\"".undump, "\"\\u{1F600 41}\"".undump, ("abc".undump rescue $!.message), "\"\\e\\a\\b\\f\\v\\r\"".undump.bytes, "\"\\\\\"".undump, "\"\\xE3\\x81\\x82\"".undump, "\"a\\x00b\"".undump.bytes
p "héllo".dump, "héllo".dump.undump, "日本".dump.undump, "\x00\xff".b.dump, "\x00\xff".b.dump.undump.bytes, "\x00\xff".b.dump.undump.encoding
p :a.casecmp(:A), :a.casecmp?(:A), :a.casecmp("a"), :b.casecmp(:a), :a.casecmp?(:b), :a.respond_to?(:intern)
r, w = IO.pipe
w.write("hi\n")
w.close
p r.gets, r.read, r.closed?, w.closed?
r.close
IO.pipe { |a, b| b.puts "x"; b.close; p a.read }
p "hello".index(nil) rescue p [$!.class, $!.message]
p "hello".rindex(nil) rescue p [$!.class, $!.message]
p ("hello".index(1) rescue $!.message), ("hello".include?(nil) rescue $!.message), ("hello".start_with?(nil) rescue $!.message)
class Widget; define_method(:as_str, &:to_s); end
class Gadget; define_method :label, &:to_s; end
puts Widget.new.as_str(7), Gadget.new.label(8)
p [1, 2, 3].map(&:to_s), [10, 20, 30].inject(0, &:+)
m = 5.method(:+)
class Adder; end
Adder.define_method(:plus, m) rescue p $!.class
n = ARGV[0].to_i
p ["x", "y", "z"][1, 4611686018427387903], [1, 2, 3][3, 4611686018427387903], "abcdef"[1, 4611686018427387903], "日本語です"[1, 4611686018427387903], "abc".byteslice(3, 4611686018427387903), [1, 2, 3][-2, 4611686018427387903]
e = [1, 2].chain([3])
p e.size, e.to_a, e.each { |x| }, e.rewind, e + [4], ([1].each + [2]).class, ([1].each + [2]).inspect, [1, 2].chain([3]).lazy.map { |x| x * 2 }.first(2), e.with_index.to_a, e.map { |x| x }, [1].chain([2]).each_slice(2).to_a, [1].chain(1..).size, [1].chain([2].each).size, Enumerator::Chain.ancestors.take(3), e.each.equal?(e), e.respond_to?(:next), [1].chain.to_a
p((5.div("x") rescue $!.message), 5.div(2.5), 5.div(Rational(3, 2)), (5.div(nil) rescue $!.message), 5.divmod(2.5), 5.remainder(Rational(3, 2)), 7.remainder(2.5), -7.remainder(2), 7.remainder(-2))
begin; "é".b + "é"; rescue Encoding::CompatibilityError => e; puts "plus: #{e.message}"; end
begin; ("é".b) << "é"; rescue Encoding::CompatibilityError => e; puts "shovel: #{e.message}"; end
begin; "é" + "é".b; rescue Encoding::CompatibilityError => e; puts "text first: #{e.message}"; end
p ("a".b + "é").encoding, ("é" + "a".b).encoding, ("é".b + "a").encoding, Encoding::CompatibilityError.superclass, Encoding::CompatibilityError.ancestors.include?(StandardError)
p "0xff".to_i(0), "12".to_i(0), "012".to_i(0), "0b11".to_i(0), "0o17".to_i(0), "-0x10".to_i(0), "09".to_i(0), "0_9".to_i(0), "1_000".to_i(0), "0x".to_i(0), "x".to_i(0)
p ("hi".ljust(5, "") rescue $!.message), "y".upto("ab").to_a, "a".upto("e", true).to_a, "9".upto("11").to_a, "az".upto("bc").to_a, ("y".."ab").to_a
p ("a".."z").include?("bb"), ("a".."z").include?("b"), ("aa".."zz").include?("bb"), ("aa".."zz").include?("b"), ("a".."z").cover?("bb"), ("a".."z") === "bb", (:a..:e).to_a, (:a..:e).include?(:c), (:a..:e).step(2).to_a
p "abc".crypt("ab"), Process.clock_getres(Process::CLOCK_MONOTONIC), Process.clock_getres(Process::CLOCK_MONOTONIC, :nanosecond), ("abc".crypt("a") rescue $!.message)
p "".reverse!, "".succ!, (+"Hello").tr!("l", "l"), (+"Hello").tr!("z", "y"), "aaa".tr("aa", ".-"), "abc".tr("a-c", "x"), 200.chr.encoding, 200.chr.ord, (0.chr + 0xc8.chr).encoding, (0.chr + 0xc8.chr)[1].ord, "x".append_as_bytes("é", 255).bytes, "x".append_as_bytes(0x41).bytes, "x".append_as_bytes("é").encoding, (+"heelloo").delete!("e"), (+"abc").delete!("z")
p 1.5.coerce("2"), (1.5.coerce("x") rescue $!.message), 1.5.coerce(Rational(1, 2)), (1.5.coerce(nil) rescue $!.message), 1.5.coerce(2), 1.5 + Rational(1, 2), Rational(1, 2) + 1.5
a = [1, 2]; a.concat(a, a); p a
b = [1]; b.concat(b); p b
r = []; ret = [1, 2].product([3, 4]) { |t| r << t }; p r, ret
p [1, 2, 3].each_slice(2) { }, [1, 2, 3].each_cons(2) { }, ([1].each_cons("l") rescue $!.message), ([1].each_slice(:a) rescue $!.message), ([1].each_slice(0) rescue $!.message)
p ([0] * 5).fill(1..2) { |i| i + 100 }, ([0] * 5).fill(7, 1..2), ([0] * 3).fill(5, 1, 5), ([0] * 3).fill { |i| i }, (([0] * 3).fill(1, "x") rescue $!.message), ([0] * 3).fill(1, -1), ([0] * 3).fill(1, 5), ([0] * 3).fill(1, -5)
h = {}; p h.public_send(:default_proc=, :a).class, h.default_proc.class
class M2; def self.foo; end; end
p M2.method(:foo).hash == M2.method(:foo).hash, { M2.method(:foo) => 1 }[M2.method(:foo)], M2.method(:foo).eql?(M2.method(:foo))
S2 = Struct.new(:verbose?, :name, :Const)
p S2.new(true, "x", 1).inspect, :+@.inspect, :-@.inspect, :[].inspect, :"a b".inspect, :a?.inspect
p "lit".freeze.equal?("lit".freeze), (-"lit").equal?(-"lit"), (-"lit").equal?("lit".freeze), "x".dedup.equal?("x".freeze)
class Sep; def to_str = "-"; end
p "a" + Sep.new, "a-b".split(Sep.new), "a".include?(Sep.new), "a-".end_with?(Sep.new), ("a".index(Sep.new)), "abc".delete(Sep.new), ("a" + 1 rescue $!.message)
class BadSep; def to_str = 1; end
p ("a" + BadSep.new rescue $!.message)
k = "k".b; h = { k => 1 }; p h.keys[0].encoding, h.keys[0].frozen?, h.keys[0].equal?(k)
