# PKey over the host's libssl: Ed25519 from fixed bytes answers fixed
# signatures; RSA, EC, DSA and DH keys generate, sign, derive and export,
# and read back what they wrote, with and without a passphrase.
#@ needs: libssl
require "openssl"

puts "-- ed25519 --"
seed = ["9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"].pack("H*")
ed = OpenSSL::PKey.new_raw_private_key("ED25519", seed)
p ed.oid, ed.raw_public_key.unpack1("H*"), ed.raw_private_key == seed
signature = ed.sign(nil, "")
p signature.unpack1("H*"), ed.verify(nil, signature, ""), ed.verify(nil, signature, "x")
pub = OpenSSL::PKey.read(ed.public_to_der)
p pub.oid, pub.public_to_pem == ed.public_to_pem, pub.verify(nil, signature, "")
p OpenSSL::PKey.new_raw_public_key("ED25519", ed.raw_public_key).compare?(ed)

puts "-- rsa --"
rsa = OpenSSL::PKey::RSA.new(2048)
p rsa.n.num_bits, rsa.e.to_i, rsa.private?, rsa.public?
data = "the data to sign"
sig = rsa.sign("SHA256", data)
p sig.bytesize, rsa.verify("SHA256", sig, data), rsa.public_key.verify("SHA256", sig, data + "!")
pss = rsa.sign_pss("SHA256", data, salt_length: :max, mgf1_hash: "SHA256")
p rsa.verify_pss("SHA256", pss, data, salt_length: :auto, mgf1_hash: "SHA256")
cipher = rsa.public_encrypt("secret", OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
p rsa.private_decrypt(cipher, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
p rsa.encrypt("secret", "rsa_padding_mode" => "oaep").then { |c| rsa.decrypt(c, "rsa_padding_mode" => "oaep") }
pem = rsa.export(OpenSSL::Cipher.new("aes-256-cbc"), "passphrase")
p pem.lines.first.chomp, pem.include?("ENCRYPTED")
p OpenSSL::PKey::RSA.new(pem, "passphrase").to_der == rsa.to_der
p OpenSSL::PKey.read(rsa.private_to_pem("aes-128-cbc", "pw"), "pw").to_der == rsa.to_der
begin
  OpenSSL::PKey.read(pem, "wrong")
rescue OpenSSL::PKey::PKeyError => e
  puts "PKeyError #{e.message.start_with?("Could not parse PKey")}"
end
p OpenSSL::PKey.read(pem) { "passphrase" }.n == rsa.n
p OpenSSL::PKey::RSA.new(rsa.public_key.to_pem).private?, rsa.params.keys.sort

puts "-- ec --"
ec = OpenSSL::PKey::EC.generate("secp384r1")
p ec.group.curve_name, ec.group.degree, ec.private?, ec.public_key.on_curve?
sig = ec.sign("SHA384", data)
p ec.verify("SHA384", sig, data), ec.dsa_verify_asn1(OpenSSL::Digest.digest("SHA384", data), ec.dsa_sign_asn1(OpenSSL::Digest.digest("SHA384", data)))
peer = OpenSSL::PKey::EC.generate("secp384r1")
p ec.derive(OpenSSL::PKey.read(peer.public_to_der)) == peer.derive(OpenSSL::PKey.read(ec.public_to_der))
p OpenSSL::PKey::EC.new(ec.to_pem).private_key == ec.private_key
point = ec.public_key
p point.to_octet_string(:compressed).bytesize, point.to_octet_string(:uncompressed).bytesize
p OpenSSL::PKey::EC::Point.new(ec.group, point.to_bn) == point
p point.mul(2) == point.add(point), ec.group.generator.mul(ec.private_key) == point
p OpenSSL::PKey::EC.builtin_curves.map(&:first).include?("prime256v1")

puts "-- dsa and dh --"
dsa = OpenSSL::PKey.generate_key(OpenSSL::PKey.generate_parameters("DSA", "dsa_paramgen_bits" => 1024))
p dsa.class, dsa.p.num_bits, dsa.verify("SHA256", dsa.sign("SHA256", data), data)
dh_params = OpenSSL::PKey.read(<<~PEM)
  -----BEGIN DH PARAMETERS-----
  MIIBCAKCAQEA//////////+t+FRYortKmq/cViAnPTzx2LnFg84tNpWp4TZBFGQz
  +8yTnc4kmz75fS/jY2MMddj2gbICrsRhetPfHtXV/WVhJDP1H18GbtCFY2VVPe0a
  87VXE15/V8k1mE8McODmi3fipona8+/och3xWKE2rec1MKzKT0g6eXq8CrGCsyT7
  YdEIqUuyyOP7uWrat2DX9GgdT0Kj3jlN9K5W7edjcrsZCwenyO4KbXCeAvzhzffi
  7MA0BM0oNC9hkXL+nOmFg/+OTxIy7vKBg8P+OxtMb61zO7X8vC7CIAXFjvGDfRaD
  ssbzSibBsu/6iGtCOGEoXJf//////////wIBAg==
  -----END DH PARAMETERS-----
PEM
alice = OpenSSL::PKey.generate_key(dh_params)
bob = OpenSSL::PKey.generate_key(dh_params)
p alice.p.num_bits, alice.params_ok?, alice.compute_key(bob.pub_key) == bob.compute_key(alice.pub_key)
p alice.derive(bob) == bob.derive(alice), OpenSSL::PKey::DH.new(dh_params.to_pem).p == dh_params.p

__END__
-- ed25519 --
"ED25519"
"d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
true
"e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
true
false
"ED25519"
true
true
true
-- rsa --
2048
65537
true
true
256
true
false
true
"secret"
"secret"
"-----BEGIN RSA PRIVATE KEY-----"
true
true
true
PKeyError true
true
false
["d", "dmp1", "dmq1", "e", "iqmp", "n", "p", "q"]
-- ec --
"secp384r1"
384
true
true
true
true
true
true
49
97
true
true
true
true
-- dsa and dh --
OpenSSL::PKey::DSA
1024
true
2048
true
true
true
true
