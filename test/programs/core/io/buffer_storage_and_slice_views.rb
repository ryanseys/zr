# IO::Buffer is the interface that two kinds share: IO::Buffer::Storage,
# which manages memory, and IO::Buffer::Slice, a view into another buffer
# at an offset from that buffer's view. A slice follows its source as the
# source advances, shrinks or grows. Each read or write makes one system
# call. Addresses are scrubbed.
require "tmpdir"
Warning[:experimental] = false
B = IO::Buffer

# The page size, which is the map alignment, depends on the machine.
def scrub(text) = text.gsub(/0x\h{9,}/, "0xX").gsub("(#{B::MAP_ALIGNMENT})", "(ALIGNMENT)")

def show(label)
  r = yield
  puts "#{label}: #{scrub(r.inspect)}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{scrub(e.message)}"
end

# ---- the classes.
show("constants") { B.constants.sort }
show("ancestors") { [B.ancestors.take(3), B::Storage.superclass, B::Slice.superclass] }
show("storage methods") { B::Storage.public_instance_methods(false).sort }
show("slice methods") { B::Slice.public_instance_methods(false).sort }
show("buffer singleton") { B.singleton_methods(false).sort }
show("version") { [B::VERSION.class, B::VERSION.positive?, B::MAP_ALIGNMENT == B::PAGE_SIZE] }
show("LOCKED") { B::LOCKED }
show("allocate") { B.allocate }
show("Storage.allocate") { B::Storage.allocate.class }
show("new class") { [B.new(4).class, B::Storage.new(4).class, B.new.size == B::DEFAULT_SIZE] }
show("Slice.for") { B::Slice.for("x") }
show("Slice.map") { B::Slice.map(nil) }
class MyStorage < B::Storage; end
show("subclass") { [MyStorage.new(2).to_s.sub(/0x\h+/, "ADDR"), MyStorage.for("ab").class, MyStorage.string(1) { |b| b.class }] }

# ---- flags that new takes.
show("internal and mapped") { B.new(4, B::INTERNAL | B::MAPPED) }
show("external") { B.new(4, B::EXTERNAL) }
show("shared internal") { B.new(4, B::INTERNAL | B::SHARED) }
show("shared private") { B.new(4, B::MAPPED | B::SHARED | B::PRIVATE) }
show("shared alone") { b = B.new(4, B::SHARED); [b.mapped?, b.shared?] }
show("unknown flag") { b = B.new(4, 1 << 20); [b.internal?, b.to_s.sub(/0x\h+/, "ADDR")] }
show("readonly new") { b = B.new(4, B::READONLY); [b.readonly?, (b.set_value(:U8, 0, 1) rescue $!.class)] }

# ---- sources.
show("source new") { B.new(4).source }
text = +"abc"
show("source for") { s = B.for(text).source; [s, s.frozen?, s.equal?(text)] }
frozen = "xyz".freeze
show("source for frozen") { B.for(frozen).source.equal?(frozen) }
show("source block") { B.for(text) { |b| b.source.equal?(text) } }
parent = B.new(8)
show("source slice") { parent.slice(1, 2).source.equal?(parent) }

# ---- a slice keeps its offset from its source's view.
show("follow") do
  buffer = B.new(6)
  buffer.set_string("abcdef")
  outer = buffer.slice(1, 4)
  inner = outer.slice(1, 2)
  before = inner.get_string
  outer.advance(1)
  [before, inner.get_string, outer.get_string, inner.source.equal?(outer)]
end
show("slice write") { b = B.new(4); b.slice(1, 2).set_string("hi"); b.get_string }
show("slice new") { b = B.for("hello"); s = B::Slice.new(b, 1, 3); [s.get_string, s.to_s.sub(/0x\h+/, "ADDR")] }
show("slice new defaults") { [B::Slice.new(B.for("hello")).size, B::Slice.new(B.for("hello"), 2).size] }
show("slice new type") { B::Slice.new("hello") }
show("slice new range") { B::Slice.new(B.new(2), 1, 2) }
show("slice again") { s = B.new(4).slice(0, 2); s.send(:initialize, B.new(4)) }
show("slice uninitialized") { s = B::Slice.allocate; [s.size, s.valid?, s.null?, s.locked?, s.source, s.to_s.sub(/0x\h+/, "ADDR")] }
show("slice uninitialized lock") { B::Slice.allocate.locked { 1 } }
show("slice uninitialized resize") { B::Slice.allocate.resize(1) }
show("slice dup") { b = B.new(4); s = b.slice(1, 2); d = s.dup; [d.class, d.source.equal?(b), d.size, d.equal?(s)] }
show("storage dup") { b = B.for("ab"); d = b.dup; [d.class, d.readonly?, d.source, d.get_string] }
show("slice copy type") { B::Slice.allocate.send(:initialize_copy, B.new(1)) }

# ---- advance.
show("advance owner") { B.new(8).advance(2) }
show("advance for") { b = B.for("hello"); b.advance(2); [b.size, b.get_string, b.source] }
show("advance slice") { b = B.new(8); s = b.slice(0, 4); s.advance(2); [s.size, s.to_s.sub(/0x\h+/, "ADDR")] }
show("advance negative") { B.new(8).slice(0, 4).advance(-1) }
show("advance too far") { B.new(8).slice(0, 4).advance(5) }
show("advance all") { s = B.new(8).slice(0, 4); s.advance(4); [s.size, s.empty?, s.valid?] }

# ---- resize of a slice, and slices that go invalid and valid again.
show("slice resize") do
  b = B.new(8)
  s = b.slice(2, 2)
  s.resize(6)
  grown = s.size
  s.resize(1)
  [grown, s.size]
end
show("slice resize past") { B.new(8).slice(2, 2).resize(7) }
show("slice resize negative") { B.new(8).slice(2, 2).resize(-1) }
show("revalidate") do
  b = B.new(8)
  b.set_string("abcdefgh")
  s = b.slice(4, 2)
  b.resize(4)
  gone = [s.valid?, s.null?, s.inspect.sub(/0x\h+/, "ADDR"), (s.get_string rescue $!.class)]
  b.resize(8)
  gone + [s.valid?, s.get_string.bytes]
end
show("invalid slice write") { b = B.new(8); s = b.slice(4, 2); b.resize(2); s.set_value(:U8, 0, 1) }
show("invalid slice of slice") { b = B.new(8); s = b.slice(4, 4).slice(1, 2); b.resize(5); [s.valid?, (s.locked { } rescue $!.message)] }

# ---- free, transfer, locks.
show("slice free") { B.new(4).slice(0, 2).free }
show("slice transfer") { B.new(4).slice(0, 2).transfer }
show("transfer") { b = B.new(4); t = b.transfer; [t.class, t.size, b.null?, b.internal?, b.to_s.sub(/0x\h+/, "ADDR")] }
show("free flags") { b = B.new(4, B::READONLY); b.free; [b.readonly?, b.internal?, b.size] }
show("locked nested") { b = B.new(4); b.locked { b.locked { [b.locked?, b.to_s.include?("LOCKED")] } } }
show("locked slice") { b = B.new(4); s = b.slice(0, 2); s.locked { [b.locked?, s.locked?, (b.free rescue $!.message)] } }
show("locked after") { b = B.new(4); b.locked { b.locked { } }; [b.locked?, b.free.null?] }
show("locked resize") { b = B.new(4); b.locked { b.resize(8) } }
show("locked slice resize") { b = B.new(4); s = b.slice(0, 2); b.locked { s.resize(3); s.size } }
show("each locks") { b = B.for("ab"); b.each(:U8).map { b.locked? } }

# ---- frozen buffers and read-only sources.
show("frozen write") { B.new(2).freeze.set_value(:U8, 0, 1) }
show("frozen readonly?") { b = B.new(2).freeze; [b.readonly?, b.frozen?, b.get_value(:U8, 0)] }
show("frozen source") { b = B.new(2).freeze; s = b.slice(0, 1); [s.readonly?, (s.set_value(:U8, 0, 1) rescue $!.class)] }
show("frozen advance") { B.new(4).slice(0, 2).freeze.advance(1) }
show("frozen free") { B.new(2).freeze.free }
show("readonly slice") { s = B.for("ab").slice(0, 1); [s.readonly?, s.to_s.sub(/0x\h+/, "ADDR")] }

# ---- bit_count, hexdump, masks, compare.
show("bit_count") { b = B.for("\xff\x01\x03".b); [b.bit_count, b.bit_count(1), b.bit_count(1, 1), b.bit_count(3)] }
show("bit_count range") { B.for("ab").bit_count(1, 2) }
show("hexdump null") { B.new(0).hexdump }
show("hexdump empty") { B.for("").hexdump }
show("hexdump width") { B.for("abcdef").hexdump(1, 4, 2) }
show("hexdump width 0") { B.for("ab").hexdump(0, 2, 0) }
show("hexdump width big") { B.for("ab").hexdump(0, 2, 1025) }
show("hexdump width negative") { B.for("ab").hexdump(0, 2, -1) }
show("inspect empty") { B.for("").inspect.sub(/0x\h+/, "ADDR") }
show("mask overlap") { b = B.new(4); b.and!(b.slice(1, 2)) }
show("mask apart") { b = B.new(4); b.set_string("\xff\xff\xff\xff".b); b.slice(0, 2).and!(b.slice(2, 2)); b.get_string.bytes }
show("mask type") { B.new(2) & "x" }
show("compare") { [B.for("a") <=> B.for("z"), B.for("z") <=> B.for("a"), B.for("ab") <=> B.for("b")] }
show("compare type") { B.new(1) <=> 1 }
show("equal") { [B.for("a") == B.for("a"), B.for("a").eql?(B.for("a"))] }

# ---- values.
show("each count") { B.for("abcd").each(:U8, 1, 2).to_a }
show("each count negative") { B.for("abcd").each(:U8, 0, -1).to_a }
show("each offset") { B.for("abcd").each(:U8, 5).to_a }
show("each_byte past") { B.for("abcd").each_byte(2, 3).to_a }
show("values u16") { B.for("abcde").values(:u16) }
show("get_values type") { B.for("ab").get_values(:U8, 0) }
show("set_values lengths") { B.new(4).set_values([:U8], 0, [1, 2]) }
show("set_values values") { B.new(4).set_values([:U8], 0, 1) }
show("type name") { B.new(2).get_value("U8", 0) }
show("type unknown") { B.new(2).get_value(:Q8, 0) }
show("clear wraps") { B.new(2).clear(257).get_string.bytes }
show("copy source offset") { B.new(4).copy(B.for("ab"), 0, nil, 3) }
show("copy source range") { B.new(4).copy(B.for("ab"), 0, 2, 1) }

# ---- one system call each, at an offset into the buffer.
Dir.mktmpdir do |dir|
  path = File.join(dir, "data")
  File.write(path, "hello")
  show("read") { r, w = IO.pipe; w.write("abcdef"); w.close; b = B.new(4); [b.read(r), b.get_string] }
  show("read offset") { r, w = IO.pipe; w.write("abc"); w.close; b = B.new(8); [b.read(r, 2, 4), b.get_string(2, 4)] }
  show("read short") { r, w = IO.pipe; w.write("ab"); b = B.new(8); n = b.read(r); w.close; [n, b.get_string(0, 2)] }
  show("read eof") { r, w = IO.pipe; w.close; B.new(8).read(r) }
  show("read past") { r, w = IO.pipe; B.new(4).read(r, 4, 2) }
  show("read readonly") { r, w = IO.pipe; B.for("ab").read(r) }
  show("write") { r, w = IO.pipe; b = B.for("hello"); [b.write(w), (w.close; r.read)] }
  show("write offset") { r, w = IO.pipe; b = B.for("hello"); [b.write(w, 2, 1), (w.close; r.read)] }
  show("write zero") { r, w = IO.pipe; B.for("hello").write(w, 5) }
  show("pread") { File.open(path) { |f| b = B.new(8); [b.pread(f, 1, 3), b.get_string(3, 4), f.pos] } }
  show("pread offset") { File.open(path) { |f| b = B.new(8); [b.pread(f, 0, 2, 4), b.get_string(2, 4)] } }
  show("pwrite") do
    File.write(path, ".....")
    File.open(path, "r+") { |f| [B.for("xyz").pwrite(f, 1, 2, 1), f.pos] } + [File.read(path)]
  end
  show("pwrite from") { File.open(path, "r+") { |f| B.for("ab").pwrite(f, 3) }; File.read(path) }
  show("map size") { File.open(path) { |f| B.map(f, 9) } }
  show("map offset") { File.open(path) { |f| B.map(f, nil, 1) } }
  show("map offset past") { File.open(path) { |f| B.map(f, nil, 5) } }
  show("map flags") { File.open(path) { |f| B.map(f, nil, 0, B::INTERNAL) } }
  show("map shared private") { File.open(path) { |f| B.map(f, nil, 0, B::SHARED | B::PRIVATE) } }
  show("map class") { File.open(path) { |f| b = B.map(f, nil, 0, B::READONLY); [b.class, b.source, b.to_s.sub(/0x\h+/, "ADDR")] } }
end

# ---- what Marshal and Ractor make of a buffer.
show("marshal") { Marshal.dump(B.new(1)) }
show("marshal slice") { Marshal.dump(B.new(1).slice(0, 1)) }
show("shareable") { [Ractor.shareable?(B.for("x")), Ractor.shareable?(B.new(1).freeze)] }
