# A preset dictionary, the stream copy, and inflate's need for the same
# dictionary: NeedDict, then the data after set_dictionary.
require "zlib"

def hex(bytes) = bytes.empty? ? "-" : bytes.unpack1("H*")

dict = "the quick brown fox jumps over the lazy dog "
text = "the lazy dog sleeps while the quick brown fox jumps and jumps"

d = Zlib::Deflate.new(6)
d.set_dictionary(dict)
packed = d.deflate(text, Zlib::FINISH)
puts "with dictionary: #{hex(packed)}"
puts "dictionary adler: #{packed[2, 4].unpack1("N")} = #{Zlib.adler32(dict)}"
d.close

i = Zlib::Inflate.new
begin
  i.inflate(packed)
rescue Zlib::NeedDict => e
  puts "#{e.class}: #{e.message}"
end
i.set_dictionary(dict)
puts "then: #{i.inflate("")}"
puts "finished: #{i.finished?}"
i.close

i = Zlib::Inflate.new
begin
  i.inflate(packed)
rescue Zlib::NeedDict
  begin
    i.set_dictionary("a different dictionary")
  rescue Zlib::Error => e
    puts "wrong dictionary: #{e.class}: #{e.message}"
  end
end
i.close

raw = Zlib::Deflate.new(6, -15)
raw.set_dictionary(dict)
rawbytes = raw.deflate(text, Zlib::FINISH)
raw.close
puts "raw with dictionary: #{hex(rawbytes)}"
ri = Zlib::Inflate.new(-15)
ri.set_dictionary(dict)
puts "raw inflated: #{ri.inflate(rawbytes)}"
ri.close

gz = Zlib::Deflate.new(6, 31)
begin
  gz.set_dictionary(dict)
rescue Zlib::Error => e
  puts "gzip refuses: #{e.class}: #{e.message}"
end
gz.close

first = "copied streams share their state so far; "
rest_a = "then they part: A"
rest_b = "then they part: B and it is longer"
d = Zlib::Deflate.new(9)
head = d.deflate(first)
copy = d.dup
a = head + d.deflate(rest_a, Zlib::FINISH)
b = head + copy.deflate(rest_b, Zlib::FINISH)
d.close
copy.close
puts "copy a: #{hex(a)}"
puts "copy b: #{hex(b)}"
puts "a reads: #{Zlib::Inflate.inflate(a)}"
puts "b reads: #{Zlib::Inflate.inflate(b)}"

__END__
with dictionary: 78bb7156101a43e114e7a4a60255956764e6a48265b09b92989702610100b9d216a5
dictionary adler: 1901465626 = 1901465626
Zlib::NeedDict: need dictionary
then: the lazy dog sleeps while the quick brown fox jumps and jumps
finished: true
wrong dictionary: Zlib::DataError: data error
raw with dictionary: 43e114e7a4a60255956764e6a48265b09b92989702610100
raw inflated: the lazy dog sleeps while the quick brown fox jumps and jumps
gzip refuses: Zlib::StreamError: stream error
copy a: 78da4bce2fc84c4d51282e294a4dcc2d5628ce482c4a5528c948cd2c028a2596a42a14e72ba425165983c4f24044a54241625189958223007f7c14f5
copy b: 78da15c8b10d80300c04c0557e0ee8d8c4221f6209ecc876c3f690e68a3b7d2a1bb282f22472481035a8f19f14918e2eb1afb3c58b29511b0e8835684113b7dbc5f80015d81ae9
a reads: copied streams share their state so far; then they part: A
b reads: copied streams share their state so far; then they part: B and it is longer
