# Ruby 4.1's openssl: HPKE (RFC 9180) suites, contexts and key
# generation; key encapsulation on a PKey; PKey#get_param; and
# X509::CRL#by_serial. Random bytes print only as their sizes.
require "openssl"

def show(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

HPKE = OpenSSL::HPKE

# ---- suites.
p256 = HPKE::Suite.new(0x10, 1, 1)
show("suite") { [p256.kem_id, p256.kdf_id, p256.aead_id, p256.frozen?] }
show("suite names") { HPKE::Suite.new("X25519", "hkdf-sha256", "chacha20-poly1305").then { |s| [s.kem_id, s.kdf_id, s.aead_id] } }
show("suite unsupported") { HPKE::Suite.new(1, 2, 3).class }
show("suite range") { HPKE::Suite.new(0x10000, 1, 1) }
show("suite negative") { HPKE::Suite.new(1, -1, 1) }
show("suite names bad") { HPKE::Suite.new("x", "y", "z") }
show("suite again") { p256.send(:initialize, 0x10, 1, 1) }
show("suite empty") { HPKE::Suite.allocate.kem_id }
show("ancestry") { [HPKE::HPKEError.superclass, HPKE::Context::Sender.superclass, HPKE::Context::Receiver.superclass] }

# ---- a round trip for each suite.
[p256, HPKE::Suite.new(0x20, 1, 3)].each do |suite|
  show("round #{suite.kem_id}") do
    key = HPKE.keygen(suite)
    public_key = suite.kem_id == 0x20 ? key.raw_public_key : key.public_key.to_bn.to_s(2)
    sender = HPKE::Context::Sender.new(suite)
    enc = sender.encap(public_key, "info")
    sealed = [sender.seal("aad", "hello"), sender.seal("", "x")]
    receiver = HPKE::Context::Receiver.new(suite)
    [key.class, enc.bytesize, receiver.decap(enc, key, "info"), sealed.map(&:bytesize),
     receiver.open("aad", sealed[0]), receiver.open("", sealed[1]),
     sender.export(16, "l") == receiver.export(16, "l"), sender.export(1, "").bytesize]
  end
end
show("seal empty") { sender = HPKE::Context::Sender.new(p256); sender.encap(HPKE.keygen(p256).public_key.to_bn.to_s(2), ""); sender.seal("", "") }
show("export none") { HPKE::Context::Sender.new(p256).export(0, "l") }
show("export negative") { HPKE::Context::Sender.new(p256).export(-1, "l") }
show("seal before encap") { HPKE::Context::Sender.new(p256).seal("", "x") }
receiver = HPKE::Context::Receiver.new(p256)
show("open bad") { receiver.open("a", "b") }
show("decap bad") { receiver.decap("x", HPKE.keygen(p256), "info") }
show("decap not a key") { receiver.decap("x", "key", "info") }
show("context bad suite") { HPKE::Context::Sender.new(1) }
show("context again") { HPKE::Context::Sender.new(p256).send(:initialize, p256) }
show("context empty") { HPKE::Context::Sender.allocate.seal("", "") }
show("keygen bad") { HPKE.keygen(1) }

# ---- key encapsulation.
x25519 = OpenSSL::PKey.generate_key("X25519")
show("encapsulate") do
  ciphertext, secret = x25519.encapsulate
  [ciphertext.bytesize, secret.bytesize, x25519.decapsulate(ciphertext) == secret]
end
show("decapsulate bad") { x25519.decapsulate("x") }
show("decapsulate type") { x25519.decapsulate(1) }

# ---- parameters.
rsa = OpenSSL::PKey::RSA.new(1024)
show("rsa e") { rsa.get_param("e").to_i }
show("rsa bits") { rsa.get_param("bits").to_i }
show("rsa n") { [rsa.get_param("n").class, rsa.get_param("n") == rsa.n] }
show("x25519 pub") { x25519.get_param("encoded-pub-key") == x25519.raw_public_key }
show("unknown") { rsa.get_param("nope") }
show("symbol") { rsa.get_param(:e) }

# ---- a CRL's revoked entry by serial.
key = OpenSSL::PKey::RSA.new(1024)
crl = OpenSSL::X509::CRL.new
crl.version = 1
crl.issuer = OpenSSL::X509::Name.parse("/CN=CA")
crl.last_update = Time.at(0)
[3, 5, 2**70].each do |serial|
  revoked = OpenSSL::X509::Revoked.new
  revoked.serial = serial
  revoked.time = Time.at(0)
  crl.add_revoked(revoked)
end
crl.sign(key, "SHA256")
show("by serial") { crl.by_serial(5).then { |r| [r.class, r.serial.to_i] } }
show("by bn") { crl.by_serial(OpenSSL::BN.new(2**70)).serial.to_i }
show("missing") { crl.by_serial(4) }
show("type") { crl.by_serial("5") }
