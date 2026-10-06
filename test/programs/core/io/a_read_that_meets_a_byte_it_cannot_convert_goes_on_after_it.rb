# A read through a converter that meets a byte it cannot convert raises
# the converter's error, drops the text that read made, and the next
# read goes on after that byte.
def through(ext_int, bytes, **opts)
  IO.pipe("#{ext_int}", **opts) do |r, w|
    w.binmode
    w.write(bytes)
    w.close
    yield r
  end
end
before = "あい"
after = "うえ"
bad = "#{before}\x80#{after}".b
through("utf-8:euc-jp", bad) do |r|
  e = (r.read rescue $!)
  p [e.class, e.error_bytes]
  p r.read == after.encode("euc-jp")
end
through("utf-8:euc-jp", bad) do |r|
  e = (r.gets rescue $!)
  p [e.class, e.error_bytes]
  p r.gets == after.encode("euc-jp")
end
pieces = ["\x42\x30", "\x44\x30", "\x00\xd8", "\x46\x30", "\x48\x30"].join.b
through("utf-16le:euc-jp", pieces, binmode: true) do |r|
  p r.getc == "あ".encode("euc-jp"), r.getc == "い".encode("euc-jp")
  e = (r.getc rescue $!)
  p [e.class, e.error_bytes]
  p r.getc == "う".encode("euc-jp"), r.getc == "え".encode("euc-jp")
end
through("utf-8:euc-jp", "a\x80b".b, invalid: :replace) { |r| p r.read }
through("utf-8:euc-jp", "a\x80b".b, undef: :replace) do |r|
  p((r.read rescue $!.class))
  p r.read
end
through("utf-8:euc-jp", "\xE3\x81a".b) do |r|
  e = (r.getc rescue $!)
  p [e.class, e.error_bytes]
  p r.getc
end
