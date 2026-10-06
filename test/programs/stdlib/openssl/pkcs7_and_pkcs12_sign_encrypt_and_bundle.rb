# PKCS7 and PKCS12 over the host's libssl: a signed message verifies
# against its signer, detached or attached; an enveloped message opens
# with the recipient's key; a PKCS12 bundle round-trips its key, its
# certificate and its chain under a passphrase.

require "openssl"

def certificate(cn, key, serial, issuer = nil, issuer_key = key)
  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = serial
  cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
  cert.issuer = issuer ? issuer.subject : cert.subject
  cert.public_key = key
  cert.not_before = Time.now - 3600
  cert.not_after = Time.now + 3600
  factory = OpenSSL::X509::ExtensionFactory.new(issuer || cert, cert)
  cert.add_extension(factory.create_extension("basicConstraints", issuer ? "CA:FALSE" : "CA:TRUE", true))
  cert.add_extension(factory.create_extension("keyUsage", issuer ? "digitalSignature, keyEncipherment" : "keyCertSign", true))
  cert.sign(issuer_key, "SHA256")
end

ca_key = OpenSSL::PKey::RSA.new(2048)
ca = certificate("ca", ca_key, 1)
key = OpenSSL::PKey::RSA.new(2048)
cert = certificate("signer", key, 2, ca, ca_key)
store = OpenSSL::X509::Store.new
store.add_cert(ca)
data = "a message to sign\n"

puts "-- signed --"
p7 = OpenSSL::PKCS7.sign(cert, key, data, [ca], OpenSSL::PKCS7::BINARY)
p p7.type, p7.detached?, p7.certificates.map { |c| c.subject.to_s }
p p7.signers.map { |s| [s.issuer.to_s, s.serial.to_i] }
p7 = OpenSSL::PKCS7.new(p7.to_der)
p p7.verify([], store, nil, OpenSSL::PKCS7::BINARY), p7.data, p7.error_string
p OpenSSL::PKCS7.new(p7.to_pem).verify([cert], store, nil, OpenSSL::PKCS7::NOVERIFY)
p OpenSSL::PKCS7.new(p7.to_der).verify([], OpenSSL::X509::Store.new, nil, OpenSSL::PKCS7::BINARY)
detached = OpenSSL::PKCS7.sign(cert, key, data, [], OpenSSL::PKCS7::DETACHED | OpenSSL::PKCS7::BINARY)
p detached.detached?, detached.data
p detached.verify([], store, data, OpenSSL::PKCS7::BINARY), detached.verify([], store, "tampered", OpenSSL::PKCS7::BINARY)
smime = OpenSSL::PKCS7.write_smime(detached, data, OpenSSL::PKCS7::DETACHED | OpenSSL::PKCS7::BINARY)
p smime.lines.first.chomp, OpenSSL::PKCS7.read_smime(smime).verify([], store, data, OpenSSL::PKCS7::BINARY)

puts "-- enveloped --"
enveloped = OpenSSL::PKCS7.encrypt([cert], data, OpenSSL::Cipher.new("AES-256-CBC"), OpenSSL::PKCS7::BINARY)
p enveloped.type, enveloped.recipients.map { |r| r.serial.to_i }
p OpenSSL::PKCS7.new(enveloped.to_der).decrypt(key, cert)
begin
  enveloped.decrypt(ca_key, ca)
rescue OpenSSL::PKCS7::PKCS7Error
  puts "PKCS7Error"
end

puts "-- pkcs12 --"
p12 = OpenSSL::PKCS12.create("passphrase", "friendly", key, cert, [ca])
parsed = OpenSSL::PKCS12.new(p12.to_der, "passphrase")
p parsed.key.to_der == key.to_der, parsed.certificate == cert, parsed.ca_certs.map(&:subject).map(&:to_s)
begin
  OpenSSL::PKCS12.new(p12.to_der, "wrong")
rescue OpenSSL::PKCS12::PKCS12Error
  puts "PKCS12Error"
end
bare = OpenSSL::PKCS12.create(nil, nil, key, cert, nil, nil, nil, nil, nil, nil)
p OpenSSL::PKCS12.new(bare.to_der).certificate == cert

