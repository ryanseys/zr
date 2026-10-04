# IO.new takes a mode through to_int (O_WRONLY alone writes) and an
# :encoding through to_str, and warns when :external_encoding or
# :internal_encoding overrides it. IO.open and File.open close through
# the program's own close after the block, as rb_check_funcall does.
path = File.join(Dir.pwd, "io2.txt")
File.write(path, "")
fd = -> { IO.sysopen(path, "w") }
m = Object.new
def m.to_int = File::WRONLY
e = Object.new
def e.to_str = "utf-8"
io = IO.new(fd.(), m); p io.closed?; io.close
io = IO.new(fd.(), mode: m); p io.closed?; io.close
io = IO.new(fd.(), "w", encoding: e); p io.external_encoding; io.close
$VERBOSE = false
io = IO.new(fd.(), "w", external_encoding: "utf-8", encoding: "iso-8859-1:iso-8859-1"); p io.external_encoding; io.close
io = IO.new(fd.(), "w", internal_encoding: "ibm866", encoding: "iso-8859-1:iso-8859-1"); p io.internal_encoding; io.close
$VERBOSE = nil
r = IO.open(fd.(), "w") do |io|
  def io.close = (super; $closed = :called; :close)
  :block
end
p r, $closed
p((IO.open(fd.(), "w") { |io| def io.close = (super; raise "from close"); 1 } rescue [$!.class, $!.message]))
p((IO.open(fd.(), "w") { |io| def io.close = (super; raise IOError, "closed stream"); 2 } rescue [$!.class, $!.message]))
File.delete(path)
path = File.join(Dir.pwd, "io4.txt")
File.write(path, "")
File.open(path) { |f| def f.close = (super; $a = :file) }
p $a
fd = IO.sysopen(path, "w")
IO.open(fd, "w") { |f| def f.close = (super; $b = :io) }
p $b
io = IO.new(IO.sysopen(path, "w"), "w")
def io.close = (super; $c = :direct)
io.close
p $c
File.delete(path)
def my_open(io)
  yield io
ensure
  io.close unless io.closed?
end
path = File.join(Dir.pwd, "io5.txt")
File.write(path, "")
my_open(File.new(path)) { |f| def f.close = (super; $a = :mine) }
p $a
r = File.open(path) { |f| def f.close = (super; $b = :file); f }
p $b, r.closed?
File.delete(path)
