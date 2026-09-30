# grapheme_clusters matches \X from each place in turn, so a byte no
# character holds is a cluster by itself; UTF-16 and UTF-32 cluster as
# UTF-8 does, and an encoding that is not Unicode has characters alone.

def show(s)
  c = s.grapheme_clusters
  p [c, c.map(&:encoding).uniq, s.each_grapheme_cluster.size]
end
show "a\xffb́c"
show "\xff\xfe".b.force_encoding("UTF-8")
show "é̂x\r\n👨‍👩‍👧🇯🇵"
show "abc"
show ""
show "é".encode("UTF-16LE")
show "a👍🏽b".encode("UTF-32BE")
show "e\xCC\x81".b
show "e\xCC\x81".force_encoding("US-ASCII")
show "日本".encode("EUC-JP")
class Sub < String; end
show Sub.new("éx")
r = +""
"ab́".each_grapheme_cluster { |g| r << "[#{g}]" }
p r

