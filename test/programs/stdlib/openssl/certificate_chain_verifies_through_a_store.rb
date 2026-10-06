# X509 over the host's libssl: a root and a leaf made here, a CSR, a CRL
# that revokes a second leaf, and a Store that verifies the chain at a
# fixed time.

require "openssl"

def name(cn) = OpenSSL::X509::Name.parse("/C=CA/O=zr/CN=#{cn}")

def certificate(serial, subject, issuer, key, signer, extensions)
  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = serial
  cert.subject = subject
  cert.issuer = (issuer || cert).subject
  cert.public_key = key
  cert.not_before = Time.utc(2026, 1, 1)
  cert.not_after = Time.utc(2036, 1, 1)
  factory = OpenSSL::X509::ExtensionFactory.new
  factory.subject_certificate = cert
  factory.issuer_certificate = issuer || cert
  extensions.each { |oid, value, critical| cert.add_extension(factory.create_extension(oid, value, critical)) }
  cert.sign(signer, "SHA256")
end

root_key = OpenSSL::PKey::EC.generate("prime256v1")
leaf_key = OpenSSL::PKey::EC.generate("prime256v1")
root = certificate(1, name("root"), nil, root_key, root_key,
                   [["basicConstraints", "CA:TRUE", true], ["keyUsage", "keyCertSign, cRLSign", true],
                    ["subjectKeyIdentifier", "hash", false]])
leaf = certificate(2, name("example.com"), root, leaf_key, root_key,
                   [["basicConstraints", "CA:FALSE", true], ["subjectAltName", "DNS:example.com, DNS:*.example.org", false],
                    ["authorityKeyIdentifier", "keyid:always", false]])
revoked = certificate(3, name("revoked"), root, leaf_key, root_key, [])

puts "-- certificates --"
[root, leaf].each do |cert|
  puts cert.subject.to_s, cert.issuer.to_s(OpenSSL::X509::Name::RFC2253), cert.serial, cert.version
  puts cert.not_before.inspect, cert.not_after.inspect, cert.signature_algorithm
  cert.extensions.each { |ext| puts "  #{ext.oid} critical=#{ext.critical?}" }
end
p leaf.verify(root_key), leaf.verify(leaf_key), root.check_private_key(root_key)
p OpenSSL::X509::Certificate.new(leaf.to_pem) == leaf, OpenSSL::X509::Certificate.new(leaf.to_der).to_der == leaf.to_der
p OpenSSL::SSL.verify_certificate_identity(leaf, "example.com"), OpenSSL::SSL.verify_certificate_identity(leaf, "a.example.org"),
  OpenSSL::SSL.verify_certificate_identity(leaf, "example.net")
p OpenSSL::X509::Certificate.load(root.to_pem + leaf.to_pem).map { |c| c.serial.to_i }

puts "-- request --"
req = OpenSSL::X509::Request.new
req.version = 0
req.subject = name("csr")
req.public_key = leaf_key
req.add_attribute(OpenSSL::X509::Attribute.new("challengePassword", OpenSSL::ASN1::Set([OpenSSL::ASN1::UTF8String("pw")])))
req.sign(leaf_key, "SHA256")
req = OpenSSL::X509::Request.new(req.to_pem)
p req.subject.to_a.map(&:first), req.verify(leaf_key), req.verify(root_key), req.attributes.map(&:oid)

puts "-- crl --"
crl = OpenSSL::X509::CRL.new
crl.version = 1
crl.issuer = root.subject
crl.last_update = Time.utc(2026, 2, 1)
crl.next_update = Time.utc(2027, 2, 1)
entry = OpenSSL::X509::Revoked.new
entry.serial = revoked.serial
entry.time = Time.utc(2026, 1, 15)
entry.add_extension(OpenSSL::X509::Extension.new("CRLReason", OpenSSL::ASN1::Enumerated(1)))
crl.add_revoked(entry)
crl.sign(root_key, "SHA256")
crl = OpenSSL::X509::CRL.new(crl.to_der)
p crl.revoked.map { |r| [r.serial.to_i, r.time, r.extensions.map(&:value)] }, crl.verify(root_key), crl.issuer == root.subject

puts "-- store --"
store = OpenSSL::X509::Store.new
store.add_cert(root)
store.time = Time.utc(2026, 6, 1)
p store.verify(leaf), store.error, store.error_string
p store.verify(root)
ctx = OpenSSL::X509::StoreContext.new(store, leaf)
p ctx.verify, ctx.chain.map { |c| c.subject.to_s }
store.add_crl(crl)
store.flags = OpenSSL::X509::V_FLAG_CRL_CHECK
p store.verify(revoked), store.error == OpenSSL::X509::V_ERR_CERT_REVOKED, store.error_string
p store.verify(leaf)
seen = []
p store.verify(leaf) { |ok, c| seen << [ok, c.error_depth]; ok }, seen
expired = OpenSSL::X509::Store.new
expired.add_cert(root)
expired.time = Time.utc(2040, 1, 1)
p expired.verify(leaf), expired.error == OpenSSL::X509::V_ERR_CERT_HAS_EXPIRED

