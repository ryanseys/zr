# reset takes a stream back to its start: the same bytes come out again,
# the totals start over, and a finished stream can be reused.
require "zlib"

def hex(bytes) = bytes.empty? ? "-" : bytes.unpack1("H*")

text = "reset me, reset me, reset me again"
d = Zlib::Deflate.new(6)
one = d.deflate(text, Zlib::FINISH)
puts "one: #{hex(one)}"
puts "totals: #{d.total_in} in, #{d.total_out} out, finished #{d.finished?}"
d.reset
puts "after reset: #{d.total_in} in, #{d.total_out} out, finished #{d.finished?}"
two = d.deflate(text, Zlib::FINISH)
puts "two: #{hex(two)}"
puts "same: #{one == two}"

d.reset
d << text[0, 10]
d.reset
three = d.deflate(text, Zlib::FINISH)
puts "reset mid-stream: #{one == three}"
puts "adler: #{d.adler} = #{Zlib.adler32(text)}"
d.close

i = Zlib::Inflate.new
puts "inflate: #{i.inflate(one)}"
puts "totals: #{i.total_in} in, #{i.total_out} out, finished #{i.finished?}"
i.reset
puts "after reset: #{i.total_in} in, #{i.total_out} out, finished #{i.finished?}"
puts "inflate again: #{i.inflate(two)}"
i.reset
half = i.inflate(one[0, 8])
i.reset
puts "half then reset then whole: #{half.inspect} #{i.inflate(one).inspect}"
i.close

begin
  i.inflate(one)
rescue Zlib::Error => e
  puts "closed: #{e.class}: #{e.message}"
end

__END__
one: 789c2b4a2d4e2d51c84dd55128c2602924a62766e60100d2350bf8
totals: 34 in, 27 out, finished true
after reset: 0 in, 0 out, finished false
two: 789c2b4a2d4e2d51c84dd55128c2602924a62766e60100d2350bf8
same: true
reset mid-stream: true
adler: 3526691832 = 3526691832
inflate: reset me, reset me, reset me again
totals: 27 in, 34 out, finished true
after reset: 0 in, 0 out, finished false
inflate again: reset me, reset me, reset me again
half then reset then whole: "reset" "reset me, reset me, reset me again"
closed: Zlib::Error: stream is not ready
