# Integer#allbits?, #anybits? and #nobits? convert the mask as rb_to_int
# does: a Float through Float#to_int, so NaN and Infinity raise
# FloatDomainError and a large Float is a Bignum. Found by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

class Mask
  def to_int = 6
end
%i[allbits? anybits? nobits?].each do |m|
  [Float::NAN, Float::INFINITY, -Float::INFINITY, 2.5, 2.0**70, 6, 2**70, Mask.new, nil, "6", 1r].each do |mask|
    try("12.#{m}(#{mask.inspect.sub(/0x\h+/, "")})") { 12.public_send(m, mask) }
  end
end
try("big.allbits?(big Float)") { (2**71 - 1).allbits?(2.0**70) }
