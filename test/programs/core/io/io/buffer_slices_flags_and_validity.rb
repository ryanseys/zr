# IO::Buffer: the flags of new buffers and slices, null buffers, slices
# that go invalid, resize, free and transfer, as CRuby 4.0 gives them.
$VERBOSE = nil
Warning[:experimental] = false
def flags(b) = %i[external? internal? mapped? shared? private? readonly? null? valid? empty?].select { |m| b.send(m) }
def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end
path = __FILE__
b = IO::Buffer.new(4, IO::Buffer::MAPPED)
s = b.slice(0, 2)
b.resize(8)
show("resize mapped slice") { flags(s) }
show("new 0") { flags(IO::Buffer.new(0)) }
show("new 0 to_s") { IO::Buffer.new(0).to_s.sub(/0x\h+/, "ADDR") }
show("new 4") { flags(IO::Buffer.new(4)) }
show("new page") { flags(IO::Buffer.new(IO::Buffer::PAGE_SIZE)) }
show("new page-1 mapped") { flags(IO::Buffer.new(IO::Buffer::PAGE_SIZE - 1, IO::Buffer::MAPPED)) }
show("new 4 readonly") { flags(IO::Buffer.new(4, IO::Buffer::READONLY)) }
show("new neg flags") { IO::Buffer.new(4, -1) }
show("new str size") { IO::Buffer.new("4") }
show("new str flags") { IO::Buffer.new(4, "1") }
show("new float size") { IO::Buffer.new(4.0) }
show("for empty") { flags(IO::Buffer.for(+"")) }
show("for empty block") { IO::Buffer.for(+"") { |b| flags(b) } }
show("string 0") { IO::Buffer.string(0) { |b| p flags(b) } }
show("slice 0") { flags(IO::Buffer.new(4).slice(0, 0)) }
show("slice new") { flags(IO::Buffer.new(4).slice(1, 2)) }
show("slice new to_s") { IO::Buffer.new(4).slice(1, 2).to_s.sub(/0x\h+/, "ADDR") }
show("slice mapped") { flags(IO::Buffer.new(IO::Buffer::PAGE_SIZE).slice(1, 2)) }
show("slice for") { flags(IO::Buffer.for(+"test").slice(1, 2)) }
show("slice for to_s") { IO::Buffer.for(+"test").slice(1, 2).to_s.sub(/0x\h+/, "ADDR") }
show("slice for frozen") { IO::Buffer.for("test".freeze) { |b| [flags(b), flags(b.slice(1, 2))] } }
show("slice map") { File.open(path) { |f| b = IO::Buffer.map(f, nil, 0, IO::Buffer::READONLY); [flags(b), flags(b.slice(1, 2))] } }
show("slice map private") { File.open(path) { |f| b = IO::Buffer.map(f, nil, 0, IO::Buffer::PRIVATE); [flags(b), flags(b.slice(1, 2)), b.slice(1,2).to_s.sub(/0x\h+/, "ADDR")] } }
show("free slice") { b = IO::Buffer.new(4); s = b.slice(1, 2); b.free; [flags(s), (s.get_string rescue $!.class)] }
show("transfer slice") { b = IO::Buffer.new(4); s = b.slice(1, 2); t = b.transfer; [flags(s), flags(t), flags(b)] }
show("resize slice out") { b = IO::Buffer.new(4); s = b.slice(2, 2); b.resize(2); [flags(s)] }
show("resize neg") { IO::Buffer.new(4).resize(-1) }
show("resize str") { IO::Buffer.new(4).resize("1") }
show("resize mapped") { b = IO::Buffer.new(IO::Buffer::PAGE_SIZE); b.resize(10); flags(b) }
show("resize mapped big") { b = IO::Buffer.new(IO::Buffer::PAGE_SIZE); b.resize(IO::Buffer::PAGE_SIZE * 2); flags(b) }
show("resize null") { b = IO::Buffer.new(0); b.resize(10); [flags(b), b.size] }
show("resize null big") { b = IO::Buffer.new(0); b.resize(IO::Buffer::PAGE_SIZE); [flags(b), b.size] }
show("resize freed") { b = IO::Buffer.new(4); b.free; b.resize(10); [flags(b), b.size] }
show("resize freed for") { b = IO::Buffer.for(+"abc"); b.free; b.resize(10); [flags(b), b.size] }
show("transfer locked") { b = IO::Buffer.new(4); b.locked { b.transfer } }
show("transfer to_s") { b = IO::Buffer.new(4); a = b.to_s; t = b.transfer; [a == t.to_s, flags(b), b.to_s.sub(/0x\h+/, "ADDR")] }
show("transfer for") { b = IO::Buffer.for(+"test"); a = b.to_s; t = b.transfer; [a == t.to_s, flags(b)] }
show("free for to_s") { b = IO::Buffer.for(+"test"); b.free; [flags(b), b.to_s.sub(/0x\h+/, "ADDR")] }
show("free new") { b = IO::Buffer.new(4); b.free; [flags(b), b.size] }
