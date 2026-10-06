# `IO::Buffer.for(string)` shares the STRING's own bytes, so a buffer write
# is visible through the string before the block ends -- CRuby's buffer
# really aliases its string's storage, and this one does too.
#
# A read of the string in the middle of the block sees the write. Nothing is
# copied in at the start or back at block exit. CRuby also locks the string
# while the block runs.
$stderr.reopen(IO::NULL)
s = +"abcdef"
IO::Buffer.for(s) do |b|
  b.set_value(:U8, 0, 0x5a)
  p s
  b.set_value(:U8, 5, 0x5a)
  p s
end
p s

# The readonly (no-block) form shares the same bytes, and refuses a write.
r = +"hello"
view = IO::Buffer.for(r)
p view.get_string
p view.readonly?
begin
  view.set_value(:U8, 0, 0x41)
rescue IO::Buffer::AccessError => e
  p [:refused, e.class]
end

# A multi-byte string keeps its encoding across a byte write.
u = +"héllo"
IO::Buffer.for(u) do |b|
  b.set_value(:U8, 0, 0x48)
end
p [u, u.encoding.to_s, u.valid_encoding?]

# `IO::Buffer.new` owns its bytes and aliases nothing.
own = IO::Buffer.new(4)
own.set_value(:U8, 0, 0x41)
p own.get_string
