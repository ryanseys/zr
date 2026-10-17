# StringIO.new reads and skips a byte order mark when the mode, or the
# option that names the encoding, starts with `bom|` (strio_init,
# rb_io_extract_modeenc).
require "stringio"

def show(string, *mode, **options)
  io = StringIO.new(string.dup, *mode, **options)
  p [io.read, io.external_encoding, io.pos]
rescue => e
  p e
end

utf8 = "﻿ab"
show(utf8, "r", encoding: "bom|utf-8")
show(utf8, "r", encoding: "BOM|UTF-8", universal_newline: false)
show(utf8, "r:bom|utf-8")
show(utf8, encoding: "bom|utf-8")
show(utf8, mode: "r:bom|utf-8")
show("ab", "r", encoding: "bom|utf-8")
show("\xFE\xFF\x00a".b, "rb", encoding: "bom|utf-16be")
show("\xFF\xFEa\x00".b, "rb:bom|utf-16le")
show(utf8, "r", external_encoding: "bom|utf-8")
show(utf8, "r", encoding: "bom|utf-8:euc-jp")
show(utf8, "r:utf-8", encoding: "bom|utf-8")
show(utf8, "r", mode: "r:bom|utf-8")
show(utf8, "r", mode: "w")
show(utf8, 0, mode: "r")

# set_encoding takes a name that only a mode knows from the mode's
# second encoding: none here, so the string is BINARY.
io = StringIO.new(utf8.dup)
io.set_encoding("bom|utf-8")
s = io.read
p s.encoding, s.bytesize, io.external_encoding
io = StringIO.new(utf8.dup)
io.set_encoding("bom|utf-8:euc-jp")
p io.external_encoding, io.string.encoding
p StringIO.new(utf8.dup).set_encoding_by_bom
