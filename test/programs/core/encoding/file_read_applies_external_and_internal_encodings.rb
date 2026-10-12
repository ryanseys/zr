# File.read tags bytes with the external encoding (default UTF-8), or a
# requested one; binread is always ASCII-8BIT; binwrite round-trips raw
# bytes. Verified against ruby.

require "tmpdir"
Dir.mktmpdir do |dir|
  path = File.join(dir, "f.txt")
  File.write(path, "café")
  p File.read(path).encoding
  p File.read(path).bytesize
  p File.binread(path).encoding
  p File.binread(path).bytes
  p File.read(path, encoding: "ISO-8859-1").encoding
  p File.read(path, encoding: "ISO-8859-1").bytes
  File.binwrite(path, [0, 255, 128].pack("C*"))
  p File.binread(path).bytes
end
