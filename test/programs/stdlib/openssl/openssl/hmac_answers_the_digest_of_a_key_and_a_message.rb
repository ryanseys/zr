# OpenSSL tier 1: versions, Digest, HMAC, KDF, Random, secure compares.
# Library version STRINGS are build-specific (zr vendors its own OpenSSL
# 3.x), so the golden prints shape checks, never the raw strings.
require "openssl"

puts "-- hmac --"
p OpenSSL::HMAC.hexdigest("SHA256", "key", "The quick brown fox")
p OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "key", "The quick brown fox")
p OpenSSL::HMAC.digest("SHA1", "key", "data").bytesize
p OpenSSL::HMAC.base64digest("SHA256", "key", "data")
h = OpenSSL::HMAC.new("key", "SHA256")
p h.class
h << "The quick "
h.update("brown fox")
p h.hexdigest
p h.digest.bytesize
p h.to_s == h.hexdigest
h2 = OpenSSL::HMAC.new("key", OpenSSL::Digest.new("SHA256"))
h2.update("The quick brown fox")
p h2.hexdigest == h.hexdigest
p h == h2
h.reset
h.update("x")
p h.hexdigest == OpenSSL::HMAC.hexdigest("SHA256", "key", "x")
begin
  OpenSSL::HMAC.new("key", "NOPE")
rescue => e
  p e.class
end

