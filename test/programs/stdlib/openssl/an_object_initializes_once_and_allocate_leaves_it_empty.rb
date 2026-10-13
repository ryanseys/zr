# Ruby 4.1's openssl: an object's initialize (and initialize_copy)
# refuses an object that already holds its struct, and a frozen one;
# `allocate` leaves an object with no struct, which says so when used.
# A dup still copies, and a copy is its own.
require "openssl"

def show(label)
  puts "#{label}: #{yield.inspect.gsub(/0x\h+/, "0xX")}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message.gsub(/0x\h+/, "0xX")}"
end

key = OpenSSL::PKey::RSA.new(1024)
name = OpenSSL::X509::Name.parse("/CN=zr")
cert = OpenSSL::X509::Certificate.new
cert.version = 2
cert.serial = 7
cert.subject = cert.issuer = name
cert.public_key = key
cert.not_before = Time.at(0)
cert.not_after = Time.at(86_400)
cert.sign(key, "SHA256")

objects = {
  "Certificate" => cert,
  "Request" => OpenSSL::X509::Request.new,
  "CRL" => OpenSSL::X509::CRL.new,
  "Name" => name,
  "Extension" => OpenSSL::X509::Extension.new("basicConstraints", "CA:FALSE"),
  "Attribute" => OpenSSL::X509::Attribute.new("challengePassword", OpenSSL::ASN1::Set([OpenSSL::ASN1::UTF8String("x")])),
  "Revoked" => OpenSSL::X509::Revoked.new,
  "Store" => OpenSSL::X509::Store.new,
  "PKCS7" => OpenSSL::PKCS7.new,
  "SPKI" => OpenSSL::Netscape::SPKI.new,
  "OCSP::Request" => OpenSSL::OCSP::Request.new,
  "Timestamp::Request" => OpenSSL::Timestamp::Request.new,
  "Cipher" => OpenSSL::Cipher.new("aes-128-cbc"),
  "RSA" => key
}
objects.each do |label, object|
  show("#{label} again") { object.send(:initialize) }
  show("#{label} copy self") { object.send(:initialize_copy, object) }
end

# A second initialize with the class's own arguments.
show("Certificate der again") { cert.send(:initialize, cert.to_der) }
show("Cipher name again") { objects["Cipher"].send(:initialize, "aes-256-cbc") }
show("RSA size again") { key.send(:initialize, 1024) }
show("Name array again") { name.send(:initialize, [["CN", "x"]]) }

# allocate leaves no struct.
show("allocated certificate") { OpenSSL::X509::Certificate.allocate.version }
show("allocated name") { OpenSSL::X509::Name.allocate.to_s }
show("allocated crl") { OpenSSL::X509::CRL.allocate.version }
show("allocated store") { OpenSSL::X509::Store.allocate.add_cert(cert) }
show("allocated pkcs7") { OpenSSL::PKCS7.allocate.type }
show("allocated then initialize") { OpenSSL::X509::Name.allocate.tap { |n| n.send(:initialize) }.to_a }

# dup and clone copy, and the copy is its own.
show("dup") do
  copy = cert.dup
  copy.serial = 9
  [cert.serial.to_i, copy.serial.to_i]
end
show("clone frozen") { cert.clone(freeze: true).then { |c| [c.frozen?, c.serial.to_i] } }
show("name dup") { name.dup.tap { |n| n.add_entry("O", "zr") }.to_s }
show("name kept") { name.to_s }

# A frozen object takes no initialize.
show("frozen initialize") { OpenSSL::X509::Revoked.allocate.freeze.send(:initialize) }
show("frozen copy") { OpenSSL::X509::Revoked.allocate.freeze.send(:initialize_copy, OpenSSL::X509::Revoked.new) }
