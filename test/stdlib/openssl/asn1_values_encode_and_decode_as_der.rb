# OpenSSL::ASN1 over the host's libssl: values encode to the DER ruby
# writes, decode back to the same classes, and malformed input raises
# ASN1Error.
#@ needs: libssl
require "openssl"

include OpenSSL

def show(value, depth = 0)
  text = case value.value
         when Array then ""
         when OpenSSL::BN then " #{value.value.to_i}"
         else " #{value.value.inspect}"
         end
  puts "#{"  " * depth}#{value.class.name.split("::").last} tag=#{value.tag} class=#{value.tag_class}#{text}"
  value.value.each { |child| show(child, depth + 1) } if value.value.is_a?(Array)
end

seq = ASN1::Sequence([
  ASN1::Integer(-129),
  ASN1::Integer(2**100),
  ASN1::Boolean(true),
  ASN1::Null(nil),
  ASN1::OctetString("\x00\xffbytes".b),
  ASN1::UTF8String("héllo"),
  ASN1::PrintableString("Printable"),
  ASN1::IA5String("ia5@example.com"),
  ASN1::ObjectId("sha256WithRSAEncryption"),
  ASN1::ObjectId("1.2.3.4.5"),
  ASN1::UTCTime(Time.utc(2026, 9, 17, 12, 30, 45)),
  ASN1::GeneralizedTime(Time.utc(2051, 1, 2, 3, 4, 5)),
  ASN1::BitString("\xA0".b).tap { |b| b.unused_bits = 5 },
  ASN1::Enumerated(3),
  ASN1::Set([ASN1::Integer(2), ASN1::Integer(1)]),
  ASN1::Integer(7, 0, :IMPLICIT),
  ASN1::UTF8String("explicit", 1, :EXPLICIT),
  ASN1::ASN1Data.new("private", 2, :PRIVATE),
])
der = seq.to_der
puts der.unpack1("H*")
decoded = ASN1.decode(der)
show(decoded)
p decoded.to_der == der
p decoded.value[8].sn, decoded.value[8].ln, decoded.value[8].oid, decoded.value[9].oid
p ASN1::ObjectId("1.2.3.4.5") == ASN1::ObjectId("1.2.3.4.5")
p ASN1::Set([ASN1::Integer(2), ASN1::Integer(1)]).to_der.unpack1("H*")

puts "-- traverse --"
ASN1.traverse(ASN1::Sequence([ASN1::Integer(1), ASN1::OctetString("x")]).to_der) do |depth, offset, header_len, length, constructed, tag_class, tag|
  p [depth, offset, header_len, length, constructed, tag_class, tag]
end
p ASN1.decode_all(ASN1::Integer(1).to_der + ASN1::Boolean(false).to_der).map { |v| v.value.is_a?(OpenSSL::BN) ? v.value.to_i : v.value }

puts "-- indefinite length --"
indefinite = ASN1::Sequence.new([ASN1::Integer(1), ASN1::EndOfContent.new])
indefinite.indefinite_length = true
p indefinite.to_der.unpack1("H*"), ASN1.decode(indefinite.to_der).indefinite_length

puts "-- errors --"
["\x02\x05\x01".b, "\x30\x80\x02\x01\x01".b, "\x06\x00".b, "".b].each do |bad|
  ASN1.decode(bad)
  puts "decoded #{bad.unpack1("H*")}"
rescue ASN1::ASN1Error => e
  puts "ASN1Error #{e.message}"
end
begin
  ASN1::ObjectId("not an oid").to_der
rescue ASN1::ASN1Error => e
  puts "ASN1Error #{e.message}"
end
begin
  ASN1::Integer("x").to_der
rescue TypeError => e
  puts "TypeError #{e.message}"
end

__END__
30819d0202ff7f020d100000000000000000000000000101ff0500040700ff62797465730c0668c3a96c6c6f13095072696e7461626c65160f696135406578616d706c652e636f6d06092a864886f70d01010b06042a030405170d3236303931373132333034355a180f32303531303130323033303430355a030205a00a01033106020102020101800107a10a0c086578706c69636974c20770726976617465
Sequence tag=16 class=UNIVERSAL
  Integer tag=2 class=UNIVERSAL -129
  Integer tag=2 class=UNIVERSAL 1267650600228229401496703205376
  Boolean tag=1 class=UNIVERSAL true
  Null tag=5 class=UNIVERSAL nil
  OctetString tag=4 class=UNIVERSAL "\x00\xFFbytes"
  UTF8String tag=12 class=UNIVERSAL "h\xC3\xA9llo"
  PrintableString tag=19 class=UNIVERSAL "Printable"
  IA5String tag=22 class=UNIVERSAL "ia5@example.com"
  ObjectId tag=6 class=UNIVERSAL "RSA-SHA256"
  ObjectId tag=6 class=UNIVERSAL "1.2.3.4.5"
  UTCTime tag=23 class=UNIVERSAL 2026-09-17 12:30:45 UTC
  GeneralizedTime tag=24 class=UNIVERSAL 2051-01-02 03:04:05 UTC
  BitString tag=3 class=UNIVERSAL "\xA0"
  Enumerated tag=10 class=UNIVERSAL 3
  Set tag=17 class=UNIVERSAL
    Integer tag=2 class=UNIVERSAL 2
    Integer tag=2 class=UNIVERSAL 1
  ASN1Data tag=0 class=CONTEXT_SPECIFIC "\a"
  ASN1Data tag=1 class=CONTEXT_SPECIFIC
    UTF8String tag=12 class=UNIVERSAL "explicit"
  ASN1Data tag=2 class=PRIVATE "private"
true
"RSA-SHA256"
"sha256WithRSAEncryption"
"1.2.840.113549.1.1.11"
"1.2.3.4.5"
true
"3106020102020101"
-- traverse --
[0, 0, 2, 6, true, :UNIVERSAL, 16]
[1, 2, 2, 1, false, :UNIVERSAL, 2]
[1, 5, 2, 1, false, :UNIVERSAL, 4]
[1, false]
-- indefinite length --
"30800201010000"
true
-- errors --
ASN1Error too long
ASN1Error EOC missing in indefinite length encoding
ASN1Error d2i_ASN1_OBJECT: invalid object encoding
ASN1Error too small
ASN1Error invalid OBJECT ID not an oid: first num too large
TypeError Cannot convert into OpenSSL::BN
