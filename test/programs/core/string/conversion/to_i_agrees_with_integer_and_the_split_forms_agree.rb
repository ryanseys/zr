# to_i, Integer() and the split forms answer over the same texts as
# ruby's: blanks, signs, underscores, prefixes, bases and separators
# of every kind, and split with a block.
texts = ["12", " 12", "12 ", "+12", "-12", "1_2", "1__2", "_12", "12_", "0x1f", "0b11", "0o17", "017", "0d19", "12abc", "abc", "", "  ", "\t\n12", "12\n", "9" * 25, "-" + "9" * 25, "1e3", "1.5", "٣"]
texts.each { |t| print t.inspect, " ", t.to_i, " ", (Integer(t) rescue "err"), " ", t.to_i(16), " ", t.to_i(2), "\n" }
lines = ["a,b,c", "a,,b", ",a,", "abc", "", "a b  c", " a b ", "a\tb\nc", "a--b--c", "日本語、テキスト"]
seps = [",", "", " ", nil, "--", "、", /,/, /\s+/, /(,)/]
lines.each do |l|
  seps.each do |s|
    [0, 2, -1].each do |limit|
      r = (s.nil? ? l.split : l.split(s, limit)) rescue $!.class
      print l.inspect, " ", s.inspect, " ", limit, " ", r.inspect, "\n"
    end
  end
end
out = []
"a,b,c".split(",") { |piece| out << piece.upcase }
p out, "a,b".split(",").map(&:frozen?), "a,b".split(",").map(&:encoding).uniq.size
$; = "-"
p "x-y".split
$; = nil

