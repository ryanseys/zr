# A string is ASCII-8BIT when the PROGRAM ASKED FOR BYTES: pack, String#b,
# Marshal.dump, Random#bytes, binread, unpack and force_encoding. The tag
# makes #length count bytes, so `Random.bytes(8).length` is 8 also when the
# draw happens to be valid UTF-8.

File.write("/tmp/_sp_enc_test.bin", "abc")

# the ones that ask for bytes
puts [65].pack("C").encoding.to_s
puts "abc".b.encoding.to_s
puts Marshal.dump(1).encoding.to_s
puts Random.bytes(4).encoding.to_s
puts File.binread("/tmp/_sp_enc_test.bin").encoding.to_s
puts IO.binread("/tmp/_sp_enc_test.bin").encoding.to_s
puts "abc".unpack("a*")[0].encoding.to_s
puts "abc".unpack("A*")[0].encoding.to_s
puts "abc".unpack("Z*")[0].encoding.to_s
puts "abc".dup.force_encoding("ASCII-8BIT").encoding.to_s
puts "abc".dup.force_encoding(Encoding::BINARY).encoding.to_s
puts "abc".dup.force_encoding(Encoding::ASCII_8BIT).encoding.to_s

# the ones that do not
puts File.read("/tmp/_sp_enc_test.bin").encoding.to_s
puts "abc".encoding.to_s
puts "abc".upcase.encoding.to_s
puts [65].pack("C").dup.force_encoding("UTF-8").encoding.to_s

# BINARY and ASCII-8BIT are one encoding, not two
p Encoding::BINARY == Encoding::ASCII_8BIT
p Encoding::BINARY.to_s
p Encoding::ASCII_8BIT.to_s

# the tag is load-bearing: a byte count, not a character count
bad = 0
1000.times { bad += 1 if Random.bytes(8).length != 8 }
p bad
m = Marshal.dump([1, 2, 3])
p m.length == m.bytesize
b = File.binread("/tmp/_sp_enc_test.bin")
p b.length

# a String reached through a mixed-type array answers #encoding, and the
# answer reaches the caller
a = ["abc", 1][0]
p a.encoding
p a.encoding.to_s
h = { "k" => [65].pack("C") }
p h["k"].encoding.to_s
def enc_of(v) = v.encoding.to_s
puts enc_of("abc")
puts enc_of([65].pack("C"))
