# A MatchData holds its text frozen, as it was when it matched: a String
# of its own for each match of a text that is not frozen, and the text
# itself when it is. A change of any kind leaves the earlier matches
# their text and gives later ones the new one.
s = +"hello world"
m1 = s.match(/o/)
m2 = s.match(/w/)
p m1.string, m1.string.frozen?, m1.string.equal?(m2.string), m1.string.equal?(s)

s << "!"
p m1.string, s.match(/!/).string, m1.string.equal?(s.match(/!/).string)
s.setbyte(0, 72)
p s.match(/H/).string, m2.string
s[0] = "J"
p s.match(/J/).string
s.insert(1, "_")
p s.match(/_/).pre_match
s.replace("new text")
p s.match(/t/).pre_match, m1.pre_match
s.upcase!
p s.match(/T/).post_match
s.force_encoding("BINARY")
p s.match(/N/).string.encoding
s.clear
p s.match(/\A\z/).string, m2[0]
s.concat("again", " and", " again")
p s.match(/and/).string
s.prepend(">")
p s.match(/>/).post_match
s.squeeze!("a")
s.tr!("g", "G")
p s.match(/G/).string
s.sub!(/aGain/, "once")
p s.match(/once/).string, $~.pre_match
s.gsub!(/n/) { "N" }
p s.match(/N/).string

# Every match of a scan holds its own String, which stays as it was.
t = +"a1 b2 c3"
found = []
t.scan(/(\w)(\d)/) { found << $~ }
p found.map(&:string).map(&:object_id).uniq.size, found.map { _1[1] }
t.gsub!(/\d/, "#")
p found.map(&:string).uniq, t

# A chilled literal is changed by its first write.
lit = "chilled text"
m = lit.match(/text/)
Warning[:deprecated] = false
lit << "!"
p m.string, lit.match(/!/).string

# A subclass keeps its class in the frozen text.
class Tag < String; end
tag = Tag.new("tagged")
p tag.match(/g+/).string.class, tag.match(/e/).string.equal?(tag.match(/d/).string)
frozen = "fixed".freeze
p frozen.match(/x/).string.equal?(frozen), frozen.match(/f/).string.equal?(frozen.match(/d/).string)
m = frozen.match(/i/).freeze
p m.string, m.dup.string.equal?(m.string)

# Two texts matched in turn each keep theirs.
a = +"alpha"
b = +"beta"
ma = a.match(/l/)
mb = b.match(/e/)
p a.match(/p/).string.equal?(ma.string), b.match(/t/).string.equal?(mb.string)
a << "!"
p a.match(/!/).string.equal?(ma.string), ma.string

# A read buffer that gives up its front does not leave a match stale.
r, w = IO.pipe
w.write("first line\nsecond line\nthird\n")
w.close
line = r.gets
p line.match(/line/).string, r.gets("nd"), r.read.match(/\w+/).string
r.close

__END__
"hello world"
true
false
false
"hello world"
"hello world!"
false
"Hello world!"
"hello world"
"Jello world!"
"J"
"new "
"hell"
"EXT"
#<Encoding:BINARY (ASCII-8BIT)>
""
"w"
"again and again"
"again and again"
">aGain and aGain"
">once and aGain"
">"
">oNce aNd aGaiN"
3
["a", "b", "c"]
["a1 b2 c3"]
"a# b# c#"
"chilled text"
"chilled text!"
Tag
false
true
true
"fixed"
true
false
false
false
"alpha"
"first line\n"
"second"
" line\nthird\n"
