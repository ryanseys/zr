# native only: the regexp engine has no wasm form
p Regexp.new("a").inspect, /a/i.inspect, /a\/b/.inspect, Regexp.new("a/b").inspect, /a/mix.to_s, /a/.to_s, /a/i.to_s, /a/.options, /a/imx.options, Regexp.new("a", true).options, Regexp.new("a", "i").options, Regexp.new("a", Regexp::EXTENDED).options, /a/.source, /a\/b/.source, Regexp.escape("a.b*c?d[e]f{g}h(i)j|k^l$m\\n \t\n-#/"), Regexp.union, Regexp.union("a.b", /c/i), Regexp.union(["x", "y"]), Regexp.union(/a/), /a/ == /a/, /a/ == /a/i, /a/.eql?(/a/), /a/.hash == /a/.hash, /a/.casefold?, /a/i.casefold?, (/a/ =~ "xa"), (/a/ =~ nil), /(?<x>a)(b)/.names, /(?<x>a)(b)/.named_captures, /(a)(b)/.names
p Regexp.last_match.class, /a/.match("ba").class, /a/.match?("ba"), /a/.match("b"), /a/ === "a", /a/ === 1, /a/.freeze.frozen?, /a/.frozen?, Regexp.new("a").frozen?, Regexp.new("(?<n>.)").names, /\d+/.match("ab12c", 3)&.[](0), /\d+/.match("ab12c", 4)&.[](0), /x/.encoding, Regexp.new("a", Regexp::IGNORECASE | Regexp::MULTILINE).inspect, /a/x.inspect, Regexp.new("a\nb", "x").source, /a/.match("a").frozen?, Regexp.escape("é"), Regexp.new("é").inspect, /./.match("é")[0], /é/.encoding, Regexp.new(/a/i).options, Regexp.new(/a/i).source, Regexp.new("a", nil).options, Regexp.new("a", false).options, Regexp.compile("b").source, Regexp.quote("a+b"), /a/.timeout, Regexp.new("a").class, Regexp.new("a").equal?(Regexp.new("a")), /a/.equal?(/a/)
2.times { p /lit/.object_id == /lit/.object_id }
r = nil
2.times { r = r.nil? ? /once/ : r.equal?(/once/) }
p r
m = "hello world".match(/(?<first>\w+) (?<second>\w+)/)
p m, m.inspect, m.to_s, m[0], m[1], m[2], m[-1], m[:first], m["first"], (m[:nope] rescue $!.message), m[1, 2], m[1..], m.pre_match, m.post_match, m.captures, m.named_captures, m.names, m.to_a, m.values_at(0, 2), m.size, m.begin(0), m.end(2), m.offset(1), m.byteoffset(2), m.string, m.string.frozen?, m.regexp, m == "hello world".match(/(?<first>\w+) (?<second>\w+)/), m.deconstruct, m.deconstruct_keys([:first]), m.match(1), m.match_length(2), (m.begin(5) rescue $!.message), m[5], (m[:x] rescue $!.class)
u = "hello world".match(/(\w+) (\w+)/)
p u, u.inspect, u[2], u.captures, u.named_captures, u.names, u.to_a, u.values_at(0, 2, -1), u.begin(2), u.end(0), "ab".match(/(?<n>a)(b)/).to_a, "ab".match(/(?<n>a)(b)/).size
m2 = "ab".match(/(x)?(b)/)
p m2, m2[1], m2.begin(1), m2.captures, m2.offset(1), m2.to_a, m2.values_at(1, 2), m2.named_captures, m2.pre_match, m2.post_match, m2.match(1), m2.match_length(1)
p "héllo".match(/l+/).begin(0), "héllo".match(/l+/).byteoffset(0), "héllo" =~ /l/, "héllo".index(/l/), "héllo".match(/(?<x>é)/).named_captures, "".match(/x*/), "".match(/x*/)[0], "abc".match(/b/, 2), "abc".match(/b/, -2), "abc".match(/b/, 1)[0], "héllo".match(/l/).pre_match, "héllo".match(/l/).post_match, "héllo".rindex(/l/), "héllo"[/é./]
p "a1b22c333".scan(/\d+/), "a1b22".scan(/([a-z])(\d+)/), "abc".scan(/x/), "aaa".scan(/a*/), "abc".scan(/(?<l>[a-z])/), ("a1b2".scan(/\d/) { |d| print d }), "test".scan(/(t)|(e)/), "héllo".scan(/./).size, ("ab".scan(/./) { p $~[0] })
puts
p "hello".sub(/l/, "L"), "hello".gsub(/l/, "L"), "hello".sub(/(l)(l)/, "\\2\\1"), "hello".gsub(/(?<x>l)/, "[\\k<x>]"), "hello".sub(/l+/) { |x| x.upcase }, "hello".gsub(/l/) { $~[0] + "!" }, "hello".gsub(/[el]/, "e" => "3", "l" => "1"), "hello".sub(/x/, "y"), "hello".gsub(/l/, "\\0\\0"), "hello".gsub(/l/, "\\&\\&"), "hello".sub(/ll/, "\\`|\\'"), "hello".gsub(/l/, "\\\\"), "a.b".gsub(".", "-"), "hello".gsub(/l/).to_a, "hello".gsub(/(l)/) { $1.upcase }, "hello".sub!(/x/, "y"), "hello".gsub!(/l/, "L"), "hello".gsub(//, "-"), "hello".gsub(/l*/, "-"), "abc".gsub(/b?/, "X"), "hello".sub(/(?<a>e)(?<b>l)/, "\\k<b>\\k<a>"), "hello world".gsub(/o/, "o" => "0"), "hello".gsub(/l/, "\\9"), "hello".sub("l", "\\0\\0"), "héllo".gsub(/l/, "L"), "hello".gsub(/L/i) { |x| x.ord.to_s }, "a-b".sub(/-/, "\\\\-"), "x".sub(/x/, "\\"), "hello".gsub(/l/, "\\\\1")
p "a,b;c".split(/[,;]/), "a1b2c".split(/\d/), "a1b2c".split(/(\d)/), "abc".split(//), "a b  c".split(/\s+/), "a b  c".split(/ /), "a,b,c".split(/,/, 2), ",a,,b,,".split(/,/), ",a,,b,,".split(/,/, -1), "abc".split(/(?=b)/), "aXbXc".split(/x/i), "a1b".split(/(?<n>\d)/), "héllo".split(/l/), "abc".split(/b*/), "".split(/,/), "a".split(/a/), "a b".split(/\s*/)
p "hello" =~ /ll/, $~, $~[0], $`, $', $&, $1, "hello" =~ /(l)(l)/, $1, $2, $3, $+, $~.pre_match, ("hello" =~ /x/), $~, $1, "abc" !~ /b/, "abc" !~ /x/, /(a)|(b)/ =~ "b", $1, $2, $+
def m; "xyz" =~ /y/; $~[0]; end
p m, $~, ("q" =~ /q/), $~[0]
[1].each { "in" =~ /n/ }
p $~[0], "ab".match?(/b/), $~[0], "abc".match(/c/), $~[0], Regexp.last_match[0], Regexp.last_match(0), (Regexp.last_match(1)), /b/.match?("abc"), $~[0], (/z/.match("abc")), $~
def n2 = $~
p n2, ("v" =~ /v/), n2, (proc { $~ }).call[0], [1].map { $~[0] }, (1.then { "w" =~ /w/; $~[0] }), $~[0]
p "abc"[/b/], "abc"[/(b)(c)/, 2], "abc"[/(?<x>b)/, "x"], "abc"[/(?<x>b)/, :x], "abc"[/x/], "abc".slice(/b./), "abc".index(/c/), "abcabc".index(/b/, 2), "abcabc".rindex(/b/), "abcabc".rindex(/b/, 3), "abc".start_with?(/a./), "abc".start_with?(/b/), "a-b".partition(/-/), "a-b-c".rpartition(/-/), "abc".partition(/x/), "aXb".partition(/x/i), "abc".end_with?("c"), ("abc".end_with?(/c/) rescue $!.class)
s = +"hello"; s[/l+/] = "L"; p s
s = +"hello"; p s.slice!(/l+/), s
s = +"hello"; s[/(e)(l)/, 2] = "_"; p s
s = +"hello"; p((begin; s[/x/] = "y"; rescue IndexError => e; e.message; end))
p :sym =~ /y/, :sym.match(/y/)[0], :sym.match?(/z/), "abc".match?(/b/, 2), "abc".match?(/a/, 1), /b/.match("abc", 2), /b/.match("abc").pre_match, "aaa".gsub(/a/) { |x| $~.begin(0) }, "x".gsub(/x/, "\\1"), "ab".gsub(/(a)|(b)/) { "#{$1}#{$2}" }, "ab".sub(/(?<x>a)/) { $~[:x] * 2 }
p "abc".each_char.grep(/[ab]/), %w[apple bob cat].grep(/a/), %w[apple bob].grep_v(/a/), [1, "a", :b].grep(/a|b/), (case "hello" when /ell/ then :yes end), "Hello World".scan(/\b\w/), "a\nb\nc".scan(/^\w$/), "a\nb".match(/a.b/m)[0], "a\nb" =~ /a$/, "AbC".match?(/abc/i), "a b c".gsub(/ (?# comment )/x, "_"), "x".match(/(?<a>x)|(?<b>y)/)[:b], "2024-01-02".match(/(\d+)-(\d+)-(\d+)/).captures.map(&:to_i), "key: value".match(/(?<k>\w+):\s*(?<v>\w+)/).named_captures(symbolize_names: true), "abc" =~ /\Ab/, "abc" =~ /c\z/, "ab\n" =~ /b$/, "ab\n" =~ /b\Z/, "a\nb" =~ /^b/, "foo123".match(/\d+/).pre_match, "a.b" =~ /\./, "tel: 555-1234".match(/(\d{3})-(\d{4})/).to_a, "AAA".gsub(/a/i, "b"), "ǅ".match?(/ǆ/i), "straße".match?(/STRASSE/i)
begin
  Regexp.new("a(")
rescue RegexpError => e
  p e.message
end
["a)", "[a", "*a", "a{2,1}", "\\k<x>", "\\p{Nope}", "(?z)", "[b-a]", "\\1", "(a)\\2", "(?<a>1)(?<a>2)\\k<a>", "(?i", "[[:nope:]]", "x++"].each do |bad|
  begin
    Regexp.new(bad)
    p [:ok, bad]
  rescue RegexpError => e
    p e.message
  end
end
p Regexp.new("a", "z").options rescue p $!.message
p Regexp.new("é").match("café")[0], Regexp.new("caf.").match("café")[0], "ñandú".match(/(?<v>[aeiouú])/)[:v], "日本語テキスト".scan(/\p{Han}+/), "日本語".match(/本/).begin(0), "日本語".match(/本/).byteoffset(0), "日本語" =~ /語/, "日本語".index(/語/), "日本語".gsub(/本/, "-"), "日本語".split(/本/), "日本語"[/本./], "日本語".sub(/(.)(.)/, "\\2\\1"), "aé".match(/\w+/)[0], "a é".match(/\s/).begin(0), "日本語".scan(/./), "日本語".match(/./).post_match
x = "interp"
p /#{x}/.source, /a#{1 + 1}b/.match("a2b")[0], /#{x}/i.options, /#{"."}/.source, /[#{x}]+/.match("pret")[0], /#{Regexp.escape(".")}/.match("a.b")[0], /#{x}/.frozen?
GC.start
big = ("ab" * 1000)
p big.scan(/ab/).size, big.gsub(/b/, "").size, big.match(/(ab)+/)[0].size, big =~ /b\z/, 100.times.map { |i| "x#{i}y".match(/\d+/)[0].to_i }.sum
r = Regexp.new('a\Kb')
p r =~ "ab", r.match("ab").begin(0), "ab".index(r), "ab" =~ r, "ab".sub(r, "Z"), "ab".scan(r), "ab".split(Regexp.new('a\K'))
p "abc".split(//, -1), "abc".split(//, 2), "a,b,,".split(/,/, -1), "a1b2c3".split(/(\d)/, 2), "".split(/,/), "".split(",", -1), "1a2b".split(/(\d)/), " one two  three ".split(" ", 2), " one two  three ".split(" ", -1), "   ".split(" ", -1), "trail   ".split(" ", 3), "a b".split(" ", 1), "abc".split("", -1), "abc".split(/(?=b)/), "a".split("a")
p "abc".gsub(/$/, "!"), "x\ny".gsub(/$/, "!"), "a\nb".gsub(/^/, ">"), "hello world".gsub(/\b/, "|"), "abc".sub(/$/, "!")
m = "hello".match(/(l)(o)/)
p m[-1], m[-2], m[-3], m[..1], m[1..], m[0, 2], (m.begin(5) rescue $!.class), (m.begin(-1) rescue $!.message), m.bytebegin(1), m.byteend(2), m.values_at(1..2), m.values_at(1..9), m.values_at(0, -1), m.deconstruct_keys([:x, :y]), ("ab".match(/(?<a>a)/).deconstruct_keys(["a"]) rescue $!.class), "ab".match(/(?<a>a)/).deconstruct_keys([:a, :b]), m.instance_variables
p(/ab/.hash == /ab/i.hash, { /ab/ => 1 }[Regexp.new("ab")], [/a/, /a/, /b/].uniq, Regexp.new("a", "ii").options, (Regexp.new("a", "z") rescue $!.message), (Regexp.new("[z-a]", Regexp::IGNORECASE | Regexp::MULTILINE) rescue $!.message))
p "ab".sub(/(?<x>b)/, "[\\1]"), "ab".sub(/(?<x>b)/, "[\\k<x>]"), "ab".sub(/(a)(b)?/, '\+'), "a.".sub(/(a)(b)?/, '\+'), Regexp.new("a\0b").to_s, Regexp.new("a\0b").inspect, Regexp.new("a/b").to_s, Regexp.new("a\tb").inspect
class Tag < String; end
tag = Tag.new("abc-123")
re = /\A[a-z]+-\d+\z/
p re === tag, re === 42, $~, re === :abc, $~, (/b/ === :abc), $~[0]
$_ = "the year 2026 arrives"
p(~ /(\d+)/, $1, (~ /x/), /a/.timeout, Regexp.timeout)
p "日本語" =~ /\w/, "日本語" =~ /\W/, "λx" =~ /\b/, "日本語" =~ /[[:word:]]/, "日" =~ /(?u)\w/, "λx" =~ /(?a)\b/, "日" =~ /(?a)[[:word:]]/, "日" =~ /(?a)\p{Word}/, " " =~ /\s/, " " =~ /[[:space:]]/, "1２" =~ /\d+/, "x" =~ /[^\W]/, "日" =~ /[\W]/, "é" =~ /\p{Upper}/i, "É" =~ /\p{^Lower}/i, "ǆ" =~ /\p{Lt}/i, "aé".match(/\w+/)[0], "ſ" =~ /\w/i, /(?u)\w/i.inspect, Regexp.union(/\w/, /(?a)\b/).source
p Regexp.new("\\C-a") =~ "\x01", Regexp.new("\\cA") =~ "\x01", Regexp.new("\\C-a").source.bytes, (Regexp.new("\\M-a") rescue $!.message), (Regexp.new("\\M-\\C-a") rescue $!.message), (Regexp.new("\\M") rescue $!.message), (Regexp.new("\\C-\\C-a") rescue $!.message), (Regexp.new("\\C-\\xZZ") rescue $!.message), Regexp.new("\\\\M-a") =~ "\\M-a", /\u{61 62}/.match("ab")[0], /A/ =~ "A", (Regexp.new("\\u{zz}") rescue $!.message)
p Regexp.linear_time?(/(a+)+/), Regexp.linear_time?(/(a)\1/), Regexp.linear_time?(/(?<x>a)\k<x>/), Regexp.linear_time?(/(?~a)/), Regexp.linear_time?("a*")
s = "\xff".dup.force_encoding("UTF-8")
p((s =~ /a/ rescue [$!.class, $!.message]), (s.match?(/a/) rescue $!.class), (s.gsub(/a/, "b") rescue $!.class), ("\xff".b =~ /a/))
p "a-9".succ, "Az".succ, "zz".succ, "a9".succ, "-9".succ, "1-z".succ, "1.9".succ, "Zz".succ
p "hello".byteindex("l"), "héllo".byteindex("l"), "héllo".byteindex(/l/, 3), ("héllo".byteindex("l", 2) rescue $!.message), "héllo".byterindex("l"), "héllo".byterindex(/l/, 4), "ab\xffc".b.scrub, "ab\xffc".dup.force_encoding("UTF-8").scrub, "ab\xffc".dup.force_encoding("UTF-8").scrub("?"), "ab\xffc".dup.force_encoding("UTF-8").scrub { |b| "<#{b.unpack1('H*')}>" }
p :b.between?(:a, :c), :b.clamp(:c, :d), [1, 2].repeated_combination(2).to_a, [1, 2, 3].repeated_combination(2).size, [1, 2].repeated_permutation(2).to_a, [1, 2].repeated_permutation(0).to_a, "ff".to_i(16), "0x1f".to_i(16), "z".to_i(36), "12".to_i(2), ("1".to_i(1) rescue $!.message), [1, 2, 3].values_at(1..9), [1, 2, 3].values_at(-2..), [1, 2, 3].values_at(0...1, 5..6)
p((begin; [1].fetch(-2); rescue IndexError => e; e.message; end), (begin; [].first(-1); rescue ArgumentError => e; e.message; end), (begin; [][-1, 0] = 1; rescue IndexError => e; e.message; end))
