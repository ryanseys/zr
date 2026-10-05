require "tmpdir"
path = File.join(Dir.tmpdir, "zr_io_encodings_#{$$}.txt")
File.write(path, "a\nb\n")
io = File.open(path, "rb")
p io.external_encoding
io.set_encoding(nil, nil)
p io.external_encoding
io.close
ARGV.replace([path, path])
p $FILENAME == path while ARGF.gets
p $FILENAME == path
r, w = IO.pipe
w.write("foobar")
r.set_encoding("utf-8", universal_newline: true)
c = r.getc
r.ungetc(c)
begin
  p r.read_nonblock(3)
rescue IOError => e
  p e
end
require "io/nonblock"
r, w = IO.pipe
w.nonblock = true
n = w.syswrite("a" * (2 * 1024 * 1024))
p n.positive? && n < 2 * 1024 * 1024
$VERBOSE = nil
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_16
$/ = $/.encode(Encoding::UTF_16)
p IO.readlines(path).map(&:encoding)
p File.open(path) { |f| f.gets }
File.delete(path)
