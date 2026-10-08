# A String keeps what a scan found about its bytes (its coderange) and
# drops it when the bytes or the encoding change, so every answer below
# reads the bytes as they are now.
def show(label, s)
  puts "#{label}: ascii_only=#{s.ascii_only?} valid=#{s.valid_encoding?} enc=#{s.encoding} bytes=#{s.bytes.inspect}"
end

s = +"café"
show "utf-8, non-ASCII", s
show "asked again", s
s.chop!
show "chop! to ASCII", s
s << "\xff".b.force_encoding("UTF-8")
show "a broken byte", s
s.chop!
show "chop! the broken byte", s

t = +"plain"
show "7bit", t
t.force_encoding("UTF-16LE")
show "as UTF-16LE", t
t.force_encoding("UTF-8")
show "back to UTF-8", t

u = +"abc"
u.force_encoding("US-ASCII")
show "US-ASCII", u
u << "\x80".b.force_encoding("US-ASCII")
show "US-ASCII with a high byte", u

v = "héllo wörld"
show "slice of non-ASCII", v[0, 1]
show "slice with non-ASCII", v[1, 3]
show "dup", v.dup
show "b", v.b
show "scrub of broken", "a\xffb".scrub("?")

w = "\xe3\x81".dup.force_encoding("UTF-8")
show "a cut UTF-8 sequence", w
w << "\x82".b.force_encoding("UTF-8")
show "completed", w

x = "\x00a".dup.force_encoding("UTF-16BE")
show "UTF-16BE", x
x << "\xd8".b.force_encoding("UTF-16BE")
show "UTF-16BE, odd length", x

y = +""
show "empty", y
y.setbyte(0, 0x41) rescue (y << "A")
show "one byte", y
y.setbyte(0, 0xe9)
show "setbyte to 0xe9", y
y.setbyte(0, 0x42)
show "setbyte back to ASCII", y

h = { "kéy" => 1, "key" => 2 }
key = +"kéy"
puts h[key].inspect
key.replace("key")
puts h[key].inspect
