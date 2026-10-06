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

