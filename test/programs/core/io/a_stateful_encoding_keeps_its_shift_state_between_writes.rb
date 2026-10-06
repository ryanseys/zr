# A stream that writes a stateful encoding, such as ISO-2022-JP, keeps
# its shift state from one write to the next and ends it at close.
[["iso-2022-jp:utf-8", "あ", "い", true],
 ["iso-2022-jp", "あ", "\x82\xa2".dup.force_encoding("sjis"), true],
 ["iso-2022-jp", "あ", "\x82\xa2".dup.force_encoding("sjis"), false],
 ["euc-jp", "あ", "\x82\xa2".dup.force_encoding("sjis"), true]].each do |enc, a, b, sync|
  r, w = IO.pipe
  w.sync = sync
  w.set_encoding(enc)
  w << a
  w << b
  w.close
  p r.read.b
end
