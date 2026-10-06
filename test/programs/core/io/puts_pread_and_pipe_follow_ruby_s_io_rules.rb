# IO#puts sends each piece to a write that takes one argument; IO#pread
# converts its arguments first and returns early for a length of 0;
# IO.pipe allocates its ends without new and set_encoding reads no BOM.
path = File.join(Dir.pwd, "pread.txt")
File.write(path, "foobar")
File.open(path) do |f|
  i = Object.new
  def i.to_int = 2
  s = Object.new
  def s.to_str = +"zz"
  p f.pread(0, 99), f.pread(0, 0, +"keep"), f.pread(i, i), f.pread(3, 0, s)
  [[Object.new, 0], [1, Object.new], [-1, 0], [1, -1], [1, 100], [1, 0, Object.new]].each do |args|
    p((f.pread(*args) rescue [$!.class, $!.message.sub(/ @ .*/, "")]))
  end
end
File.open(path, "w") { |f| p((f.pread(1, 0) rescue [$!.class, $!.message])) }
f = File.open(path); f.close
p((f.pread(1, 0) rescue [$!.class, $!.message]))
class << (log = +"")
end
io = File.open(path, "w")
def io.write(str) = (($w ||= []) << str; str.size)
io.puts("a", "b\n", ["c"], nil)
io.close
p $w
o = Object.new
def o.write(*a) = (($o ||= []) << a; 1)
$stdout = o
puts "x", "y"
$stdout = STDOUT
p $o
File.delete(path)
[["BOM|UTF-8"], ["UTF-8:ISO-8859-1"], ["BOM|UTF-8:ISO-8859-1"], ["UTF-8", "UTF-16BE"], [Encoding::UTF_8]].each do |args|
  IO.pipe(*args) { |r, w| p [args, r.external_encoding, r.internal_encoding, w.external_encoding, w.internal_encoding] }
end
IO.pipe(external_encoding: "UTF-8") { |r, w| p r.external_encoding }
class SubIO < IO
  def self.new(*) = raise("new called")
  def initialize(*a)
    ($init ||= 0)
    $init += 1
    super
  end
end
r, w = SubIO.pipe
p r.class, w.class, $init
File.binwrite("b.txt", "﻿hi"); File.open("b.txt") { |f| f.set_encoding("BOM|UTF-8"); p f.read.bytes, f.external_encoding }; File.open("b.txt", "r:BOM|UTF-8") { |f| p f.read.bytes }; File.delete("b.txt")
