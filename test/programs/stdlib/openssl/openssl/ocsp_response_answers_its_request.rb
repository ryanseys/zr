# OCSP over the host's libssl: a request for two certificates with a
# nonce, a responder that answers one good and one revoked, and a client
# that verifies the response, matches the nonce and reads each status.

require "openssl"

def certificate(cn, key, serial, issuer = nil, issuer_key = key, extensions = [])
  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = serial
  cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
  cert.issuer = issuer ? issuer.subject : cert.subject
  cert.public_key = key
  cert.not_before = Time.utc(2026, 1, 1)
  cert.not_after = Time.utc(2036, 1, 1)
  factory = OpenSSL::X509::ExtensionFactory.new(issuer || cert, cert)
  extensions.each { |oid, value| cert.add_extension(factory.create_extension(oid, value)) }
  cert.sign(issuer_key, "SHA256")
end

ca_key = OpenSSL::PKey::EC.generate("prime256v1")
ca = certificate("ca", ca_key, 1, nil, ca_key, [["basicConstraints", "CA:TRUE"]])
responder_key = OpenSSL::PKey::EC.generate("prime256v1")
responder = certificate("responder", responder_key, 2, ca, ca_key, [["extendedKeyUsage", "OCSPSigning"]])
good = certificate("good", OpenSSL::PKey::EC.generate("prime256v1"), 10, ca, ca_key)
revoked = certificate("revoked", OpenSSL::PKey::EC.generate("prime256v1"), 11, ca, ca_key)

puts "-- request --"
good_id = OpenSSL::OCSP::CertificateId.new(good, ca, OpenSSL::Digest.new("SHA256"))
revoked_id = OpenSSL::OCSP::CertificateId.new(revoked, ca)
p good_id.serial.to_i, good_id.hash_algorithm, revoked_id.hash_algorithm, good_id.issuer_name_hash.bytesize
p good_id.cmp(OpenSSL::OCSP::CertificateId.new(good_id.to_der)), good_id.cmp_issuer(revoked_id), good_id.cmp(revoked_id)
request = OpenSSL::OCSP::Request.new
request.add_certid(good_id)
request.add_certid(revoked_id)
request.add_nonce("0123456789abcdef")
request = OpenSSL::OCSP::Request.new(request.to_der)
p request.certid.map { |id| id.serial.to_i }, request.signed?
signed = request.dup
signed.sign(responder, responder_key, [ca])
store = OpenSSL::X509::Store.new
store.add_cert(ca)
p signed.signed?, signed.verify([], store), request.verify([], store)

puts "-- response --"
basic = OpenSSL::OCSP::BasicResponse.new
basic.copy_nonce(request)
basic.add_status(good_id, OpenSSL::OCSP::V_CERTSTATUS_GOOD, nil, nil, Time.utc(2026, 9, 1), Time.utc(2035, 9, 1), [])
basic.add_status(revoked_id, OpenSSL::OCSP::V_CERTSTATUS_REVOKED, OpenSSL::OCSP::REVOKED_STATUS_KEYCOMPROMISE,
                 Time.utc(2026, 8, 1), Time.utc(2026, 9, 1), nil, nil)
basic.sign(responder, responder_key, [responder])
response = OpenSSL::OCSP::Response.create(OpenSSL::OCSP::RESPONSE_STATUS_SUCCESSFUL, basic)
response = OpenSSL::OCSP::Response.new(response.to_der)
p response.status, response.status_string

puts "-- client --"
basic = response.basic
p request.check_nonce(basic), OpenSSL::OCSP::Request.new.check_nonce(basic), basic.verify([], store)
basic.status.each do |id, status, reason, revoked_at, this_update, next_update, extensions|
  p [id.serial.to_i, status, reason, revoked_at, this_update, next_update, extensions]
end
single = basic.find_response(revoked_id)
p single.cert_status, single.revocation_reason, single.revocation_time, single.this_update, single.next_update
p single.check_validity, single.certid.cmp(revoked_id), basic.responses.size
p basic.find_response(OpenSSL::OCSP::CertificateId.new(responder, ca))
begin
  basic.find_response(good_id).revocation_reason
rescue OpenSSL::OCSP::OCSPError => e
  puts "OCSPError #{e.message}"
end
p OpenSSL::OCSP::Response.create(OpenSSL::OCSP::RESPONSE_STATUS_TRYLATER, nil).then { |r| [r.status_string, r.basic] }

