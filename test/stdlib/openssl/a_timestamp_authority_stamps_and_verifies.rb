# OpenSSL::Timestamp over the host's libssl: a request for a SHA-256
# imprint, a factory that answers it with a token from a TSA certificate,
# and a verification of that token against the request and a store.
#@ needs: libssl
require "openssl"

def certificate(cn, key, serial, issuer, issuer_key, extensions)
  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = serial
  cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
  cert.issuer = issuer ? issuer.subject : cert.subject
  cert.public_key = key
  cert.not_before = Time.utc(2026, 1, 1)
  cert.not_after = Time.utc(2036, 1, 1)
  factory = OpenSSL::X509::ExtensionFactory.new(issuer || cert, cert)
  extensions.each { |oid, value, critical| cert.add_extension(factory.create_extension(oid, value, critical)) }
  cert.sign(issuer_key, "SHA256")
end

ca_key = OpenSSL::PKey::RSA.new(2048)
ca = certificate("root", ca_key, 1, nil, ca_key, [["basicConstraints", "CA:TRUE", true], ["keyUsage", "keyCertSign, cRLSign", true]])
tsa_key = OpenSSL::PKey::RSA.new(2048)
tsa = certificate("tsa", tsa_key, 2, ca, ca_key, [["extendedKeyUsage", "timeStamping", true]])
plain = certificate("plain", tsa_key, 3, ca, ca_key, [])

puts "-- request --"
data = "the document"
request = OpenSSL::Timestamp::Request.new
p request.version, request.cert_requested?, request.nonce, request.policy_id
request.algorithm = "SHA256"
request.message_imprint = OpenSSL::Digest.digest("SHA256", data)
request.policy_id = "1.2.3.4.5"
request.nonce = 42
request.cert_requested = true
request = OpenSSL::Timestamp::Request.new(request.to_der)
p request.algorithm, request.message_imprint.bytesize, request.policy_id, request.nonce.to_i, request.cert_requested?
begin
  OpenSSL::Timestamp::Request.new.to_der
rescue OpenSSL::Timestamp::TimestampError => e
  puts "TimestampError #{e.message}"
end

puts "-- factory --"
factory = OpenSSL::Timestamp::Factory.new
factory.gen_time = Time.utc(2026, 9, 17, 8, 0, 0)
factory.serial_number = 7
factory.allowed_digests = ["sha256", "sha512"]
factory.default_policy_id = "1.2.3.4.6"
factory.additional_certs = [ca]
response = factory.create_timestamp(tsa_key, tsa, request)
response = OpenSSL::Timestamp::Response.new(response.to_der)
p response.status.to_i, response.failure_info, response.status_text
info = response.token_info
p info.version, info.policy_id, info.algorithm, info.serial_number.to_i, info.gen_time, info.ordering, info.nonce.to_i
p info.message_imprint == request.message_imprint, response.tsa_certificate.subject.to_s, response.token.type
p OpenSSL::Timestamp::TokenInfo.new(info.to_der).serial_number.to_i

puts "-- verify --"
store = OpenSSL::X509::Store.new
store.add_cert(ca)
store.time = Time.utc(2026, 9, 17)
p response.verify(request, store, [tsa]).equal?(response)
other = OpenSSL::Timestamp::Request.new(request.to_der)
other.message_imprint = OpenSSL::Digest.digest("SHA256", "another document")
begin
  response.verify(other, store)
rescue OpenSSL::Timestamp::TimestampError => e
  puts "TimestampError #{e.message.start_with?("TS_RESP_verify_response")}"
end

puts "-- refusals --"
begin
  factory.create_timestamp(tsa_key, plain, request)
rescue OpenSSL::Timestamp::TimestampError => e
  puts "TimestampError #{e.message}"
end
factory.serial_number = nil
begin
  factory.create_timestamp(tsa_key, tsa, request)
rescue OpenSSL::Timestamp::TimestampError => e
  puts "TimestampError #{e.message}"
end
factory.serial_number = 8
factory.allowed_digests = ["sha1"]
rejected = factory.create_timestamp(tsa_key, tsa, request)
p rejected.status.to_i, rejected.failure_info, rejected.status_text, rejected.token

__END__
-- request --
1
true
nil
nil
"SHA256"
32
"1.2.3.4.5"
42
true
TimestampError Message imprint missing algorithm
-- factory --
0
nil
[]
1
"1.2.3.4.5"
"SHA256"
7
2026-09-17 08:00:00 UTC
false
42
true
"/CN=tsa"
:signed
7
-- verify --
true
TimestampError true
-- refusals --
TimestampError Certificate does not contain the timestamping extension: invalid signer certificate purpose
TimestampError @serial_number must be set.
2
:BAD_ALG
["Message digest algorithm is not supported."]
nil
