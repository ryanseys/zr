# A directive that writes arbitrary bytes keeps the buffer's encoding;
# `U` first makes it UTF-8; only `m`, `M` and `u` (or none) make it US-ASCII.
def show(items, template, buffer)
  items.pack(template, buffer:)
  p [template, buffer, buffer.encoding, buffer.valid_encoding?]
end

show([65], "C", +"é")
show([233], "C", +"ab")
show([233], "U", +"ab".b)
show([233], "U", +"ab")
show([65, 66], "UC", +"".b)
show([65, 66], "CU", +"".b)
show([65], "U", "ab".encode("UTF-16LE").force_encoding("BINARY"))
show(["x"], "m", +"ab")
show(["x"], "M", +"ab".b)
show(["x"], "u", "ab".encode("EUC-JP"))
show([], "", +"ab")
show([200], "C", +"ab".force_encoding("US-ASCII"))
show([1], "U", +"ab".force_encoding("US-ASCII"))
show(["x", 1], "mU", +"".b)
show([1, "x"], "Um", +"".b)
show(["é"], "a*", "ab".encode("Windows-1252"))

p [65].pack("U").encoding, ["x"].pack("m").encoding, [].pack("").encoding
