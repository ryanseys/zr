# IO::Buffer is a window on bytes: its own, or a String's. A buffer made
# `for` a String reads and writes that String's bytes in place, which is
# what ruby means by locking the string for the block. Addresses in the
# report are the object's, so this file scrubs them.
$stderr.reopen(IO::NULL)
p IO::Buffer::PAGE_SIZE.class
p IO::Buffer::DEFAULT_SIZE
p [IO::Buffer::EXTERNAL, IO::Buffer::INTERNAL, IO::Buffer::MAPPED, IO::Buffer::SHARED, IO::Buffer::LOCKED, IO::Buffer::PRIVATE, IO::Buffer::READONLY]
p [IO::Buffer::LITTLE_ENDIAN, IO::Buffer::BIG_ENDIAN, IO::Buffer::HOST_ENDIAN, IO::Buffer::NETWORK_ENDIAN]
p IO::Buffer.size_of(:U8)
p IO::Buffer.size_of([:U32, :F64])
b = IO::Buffer.new(8)
p [b.size, b.external?, b.internal?, b.readonly?, b.valid?, b.empty?]
b.set_value(:U16, 0, 0x1234)
p b.get_value(:U16, 0)
p b.get_string
p b.to_s
p b.inspect.sub(/0x\h{16}/, "0xADDR")
b.set_string("hi", 4)
p b.get_string(4, 2)
p b.slice(0, 2).get_string
p b.hexdump.class
s = +"abcdef"
v = IO::Buffer.for(s)
p [v.size, v.readonly?, v.external?, v.get_string]
begin; v.set_value(:U8, 0, 65); rescue => e; p [e.class, e.message]; end
IO::Buffer.for(s) { |w| w.set_value(:U8, 0, 90); p [w.readonly?, s] }
p s
p IO::Buffer.string(3) { |w| w.set_string("xyz") }
p [b.get_values([:U8, :U8], 0)]
c = IO::Buffer.new(4)
b.copy(c, 0, 4)
p c.get_string
p IO::Buffer.new(2).clear(7).get_string.bytes
begin; IO::Buffer.new(2).get_value(:U8, 5); rescue => e; p [e.class, e.message]; end
p [IO::Buffer::AccessError.superclass, IO::Buffer::AllocationError.superclass, IO::Buffer::InvalidatedError.superclass, IO::Buffer::LockedError.superclass, IO::Buffer::MaskError.superclass]
p IO::Buffer.superclass
b = IO::Buffer.new(8)
%i[U8 S8 U16 S16 U32 S32 U64 S64 u16 s16 u32 s32 u64 s64 F32 F64 f32 f64].each { |t| print t, "=", IO::Buffer.size_of(t), " " }
puts
b.set_value(:u16, 0, 0x1234); p b.get_string(0, 2).bytes
b.set_value(:S8, 0, -1); p b.get_value(:S8, 0)
b.set_value(:F64, 0, 1.5); p b.get_value(:F64, 0)
b.set_value(:f32, 0, 1.5); p [b.get_value(:f32, 0), b.get_string(0,4).bytes]
p IO::Buffer.new(4).values(:U8, 0)
p IO::Buffer.new(4).each(:U8, 0).to_a
p IO::Buffer.new(0).empty?
p IO::Buffer.for("abc").slice(1).get_string
p IO::Buffer.for("abc") <=> IO::Buffer.for("abd")
d = IO::Buffer.new(2); d.set_string("\x0f\xf0".b); p (d & IO::Buffer.for("\xff\x00".b)).get_string.bytes
begin; IO::Buffer.new(2).set_value(:BAD, 0, 1); rescue => e; p [e.class, e.message]; end
begin; IO::Buffer.for("x").resize(4); rescue => e; p [e.class, e.message]; end
e2 = IO::Buffer.new(2); e2.free; p [e2.null?, e2.size]
begin; e2.get_string; rescue => e; p [e.class, e.message]; end
__END__
Integer
65536
[1, 2, 4, 8, 32, 64, 128]
[4, 8, 4, 8]
1
12
[8, false, true, false, true, false]
4660
"\x124\x00\x00\x00\x00\x00\x00"
"#<IO::Buffer 0x000000090f3356c0+8 INTERNAL>"
"#<IO::Buffer 0xADDR+8 INTERNAL>\n0x00000000  12 34 00 00 00 00 00 00                         .4......"
"hi"
"\x124"
String
[6, true, true, "abcdef"]
[IO::Buffer::AccessError, "Buffer is not writable!"]
[false, "Zbcdef"]
"Zbcdef"
"xyz"
[[18, 52]]
"\x00\x00\x00\x00"
[7, 7]
[ArgumentError, "Type extends beyond end of buffer! (offset=5 > size=2)"]
[RuntimeError, RuntimeError, RuntimeError, RuntimeError, ArgumentError]
Object
U8=1 S8=1 U16=2 S16=2 U32=4 S32=4 U64=8 S64=8 u16=2 s16=2 u32=4 s32=4 u64=8 s64=8 F32=4 F64=8 f32=4 f64=8 
[52, 18]
-1
1.5
[1.5, [0, 0, 192, 63]]
[0, 0, 0, 0]
[[0, 0], [1, 0], [2, 0], [3, 0]]
true
"bc"
-1
[15, 0]
[ArgumentError, "Invalid type name!"]
[IO::Buffer::AccessError, "Cannot resize external buffer!"]
[true, 0]
