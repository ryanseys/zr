# MatchData#match and #match_length raise an IndexError for a group
# past the last one, as match_nth does; a group that did not take part
# is nil.
def show(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

m = /(a)(b)?(?<n>c)?/.match("xa")
show("groups") { [m.match(0), m.match(1), m.match(2), m.match(3)] }
show("lengths") { [m.match_length(0), m.match_length(1), m.match_length(2)] }
n = /(?<x>a)(?<y>b)?/.match("a")
show("names") { [n.match(:x), n.match("x"), n.match(:y), n.match_length(:x), n.match_length("y")] }
[4, 5, -1, -5, :zz, "zz", 1.9, nil].each do |i|
  show("match(#{i.inspect})") { m.match(i) }
  show("match_length(#{i.inspect})") { m.match_length(i) }
end
show("multibyte") { /(é)(😀)/.match("aé😀").then { |x| [x.match(2), x.match(1).encoding, x.match_length(2)] } }
