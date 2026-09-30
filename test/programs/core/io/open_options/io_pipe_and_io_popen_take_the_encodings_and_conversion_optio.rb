# IO.pipe and IO.popen take the encodings and conversion options that an
# open takes; popen gives the rest to spawn.
r, w = IO.pipe("utf-8", "iso-8859-1", invalid: :replace, replace: "?")
w.write("a\xffb")
w.close
p r.read
IO.popen("printf '\\351'", "r:iso-8859-1") { |io| p [io.read, io.external_encoding] }
IO.popen("printf '\\351'", "rb") { |io| p io.read.encoding }
IO.popen("printf 'x'", external_encoding: "binary") { |io| p io.read.encoding }
IO.popen(["printf", "y"], mode: "rb") { |io| p [io.read, io.binmode?] }
r, w = IO.pipe(binmode: true)
p [r.binmode?, w.binmode?, r.external_encoding]
