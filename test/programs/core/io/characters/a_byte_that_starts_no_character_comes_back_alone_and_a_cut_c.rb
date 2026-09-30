# A byte that starts no character comes back alone, and a character that
# the stream ends inside comes back with the bytes it has.
def pipe(data)
  r, w = IO.pipe
  w.write(data.b)
  w.close
  r
end
p pipe("\xE3\x81a").each_char.to_a
p pipe("\xE3\x81").each_char.to_a
p pipe("\xff\xfe").each_char.map(&:valid_encoding?)
p pipe("aé").each_codepoint.to_a
p((pipe("a\xff").each_codepoint.to_a rescue $!))
p pipe("abc").each_char.with_index.to_a
