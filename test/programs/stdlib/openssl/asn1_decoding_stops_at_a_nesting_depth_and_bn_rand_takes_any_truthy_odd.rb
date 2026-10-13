# OpenSSL::ASN1.decode refuses constructed values nested deeper than its
# limit, and BN.rand makes the number odd for any truthy `odd`.
require "openssl"

def nested(depth)
  inner = OpenSSL::ASN1::Null.new(nil)
  depth.times { inner = OpenSSL::ASN1::Sequence.new([inner]) }
  inner.to_der
end

def depth_of(value)
  depth = 0
  while value.is_a?(OpenSSL::ASN1::Constructive)
    value = value.value.first
    depth += 1
  end
  depth
end

[1, 199, 200, 201, 500].each do |depth|
  print "depth #{depth}: "
  puts depth_of(OpenSSL::ASN1.decode(nested(depth)))
rescue OpenSSL::ASN1::ASN1Error => e
  puts "#{e.class}: #{e.message}"
end

print "decode_all past the limit: "
begin
  OpenSSL::ASN1.decode_all(nested(250))
rescue OpenSSL::ASN1::ASN1Error => e
  puts e.message
end
puts "traverse past the limit: #{OpenSSL::ASN1.traverse(nested(250)) { break :walked }.inspect}"

[true, 1, "yes", :odd, false, nil].each do |odd|
  odds = Array.new(20) { OpenSSL::BN.rand(16, 0, odd).odd? }
  puts "rand odd=#{odd.inspect}: #{odds.all? ? "always odd" : "parity varies or even"}"
end
puts "rand bits: #{Array.new(20) { OpenSSL::BN.rand(16, 0, 1).num_bits <= 16 }.all?}"
