# String methods over ASCII bytes, Symbol's mirrors, and Kernel's
# conversions.
s = "hello world"
p s[0], s[-1], s[20], s[1, 3], s[1, 0], s[11, 2], s[12, 2], s[1..3], s[1...3], s[-3..], s[..1], s[5..2], s[20..], s["wor"], s["xyz"]
p s.chars.first(3), s.bytes.first(3), s.bytesize, s.getbyte(0), s.ord, "".chr, s.chr
p s.start_with?("hell"), s.start_with?("x", "he"), s.end_with?("ld"), s.end_with?("x")
p s.delete_prefix("hello "), s.delete_suffix(" world"), s.delete_prefix("x")
p s.swapcase, "Hello".swapcase, "abc".upcase!, "ABC".upcase!, "abc".capitalize!, "Abc".capitalize!
p "  hi  ".strip, "  hi  ".lstrip, "  hi  ".rstrip, "\t\nhi\n ".strip, "hi".strip!, " hi".strip!
p "hi\n".chomp, "hi\r\n".chomp, "hi\r".chomp, "hi".chomp, "hi!".chomp("!"), "hi\n\n".chomp(""), "hi".chomp!, "hi\n".chomp!
p "hi".chop, "hi\r\n".chop, "".chop, "aaabbbccc".squeeze
p "a\nb\nc".lines, "a\nb\n".lines, "a\nb".lines(chomp: true), "".lines, "a\nb".each_line.to_a
p "a b  c".split, " a b ".split, "a,b,c".split(","), "a,b,,".split(","), "a,b,,".split(",", -1), "abc".split(""), "a b c".split(" ", 2), "a,b,c".split(",", 2), "".split(",")
p "hello".sub("l", "L"), "hello".gsub("l", "L"), "hello".sub("x", "y"), "hello".gsub("l") { |m| m.upcase }, "hello".sub!("z", ""), "hello".gsub!("l", "")
p "hello".index("l"), "hello".index("l", 3), "hello".index("z"), "hello".rindex("l"), "hello".rindex("l", 2), "hello".index("", 5), "hello".index("l", -2)
p "hello".count("l"), "hello".delete("l"), "hello".tr("el", "ip"), "hello".tr("lo", "x")
p "hi".center(6), "hi".center(7, "*"), "hi".ljust(5, "-"), "hi".rjust(5, "-"), "hello".center(3)
p "42".to_i, " 42abc".to_i, "-7".to_i, "+7".to_i, "abc".to_i, "1_000".to_i, "1__0".to_i, "_1".to_i, "".to_i
p "aBc".casecmp("ABC"), "aBc".casecmp?("ABC"), "a".casecmp("b"), "a".casecmp(1)
p "abc".ascii_only?, "hello".insert(2, "XX"), "hello".insert(-1, "!"), "hello".insert(-3, "_"), "a".prepend("b", "c"), "a".concat("b", "c")
p "abc".replace("xyz"), "abc".clear, "abc".setbyte(0, 65), "abc".tap { |t| t.setbyte(0, 65) }
p "hello" <=> "help", "a" < "b", "b".between?("a", "c"), "a".clamp("b", "c")
p :abc[0], :abc.length, :abc.size, :abc.upcase, :Abc.downcase, :abc.capitalize, :aBc.swapcase, :abc.succ, :abc.start_with?("a"), :abc.end_with?("c"), :abc.to_sym, :abc.empty?, :"".empty?
p Integer("42"), Integer("-42"), Integer("0x1f"), Integer("0b101"), Integer("0o17"), Integer("017"), Integer("0d19"), Integer("1_000"), Integer(" 42 "), Integer(42), Integer(nil, exception: false), Integer("x", exception: false), Integer("", exception: false), Integer("1__0", exception: false), Integer("_1", exception: false), Integer("0x", exception: false), Integer("08", exception: false)
begin; Integer("abc"); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Integer(nil); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Integer([]); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Integer(42, 10); rescue => e; puts "#{e.class}: #{e.message}"; end
p Integer("ff", 16), Integer("0xff", 16), Integer("0b11", 16), Integer("0b11", 2), Integer("0o17", 8), Integer("017", 8), Integer("017", 10), Integer("017", 16), Integer("z", 36), Integer("0x12", 0), Integer("-0xff", 16), Integer("ff", -16), Integer("1_0", 2), Integer("0d19", 16), Integer("0_17"), Integer("0x1f", 10, exception: false), Integer("0x", 16, exception: false)
begin; Integer("ff", 1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Integer("ff", -37, exception: false); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Integer("0x_ff", 16); rescue => e; puts "#{e.class}: #{e.message}"; end
p String(1), String(:a), String(nil), Array(nil), Array([1]), Array(1..3), Array(1), Array(a: 1)
p 5.tap { |x| x + 1 }, 5.then { |x| x + 1 }, 5.yield_self { |x| x * 2 }, 5.then.class
warn "to stderr"
warn "a", "b"
warn
p "abc".frozen?, "abc".dup.frozen?, "abc".freeze.frozen?
begin; "abc".freeze.replace("x"); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; "abc".setbyte(5, 1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; "".ord; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; "hi".center(5, ""); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; "hi".count; rescue => e; puts "#{e.class}: #{e.message}"; end
s = "abcdef"
s[0] = "z"
p s
s[1, 2] = "XY"
p s
s[1..2] = "q"
p s
s["z"] = "A"
p s
begin; s["nope"] = "x"; rescue => e; p e; end
s[-1] = "!"
p s
begin; s[9] = "x"; rescue => e; p e; end
s[2, 0] = "ins"
p s
s[1..] = ""
p s
begin; s[0] = 1; rescue => e; p e; end
s = "abcdef"
[[9], [-10], [1, -1], [9, 1], [6], [6, 0], [9..], [-9..1], [2..1], [1...1]].each do |a|
  t = s.dup
  begin
    t.send(:[]=, *a, "x")
    p t
  rescue => e
    p e
  end
end
f = "abc".freeze
begin; f[0] = "z"; rescue => e; p e, e.receiver.equal?(f); end
begin; s[0, 1, 2] = "x"; rescue => e; p e; end
p(s[0] = "Q")
begin; f[0] = "z"; rescue FrozenError => e; puts e.send(:message); end
puts f
p (9..).inspect, (..9).inspect, (nil..nil).inspect, (9..).to_s, (..9).to_s, (nil..nil).to_s, (nil...nil).inspect, ("a"..).to_s, ("a"..).inspect
