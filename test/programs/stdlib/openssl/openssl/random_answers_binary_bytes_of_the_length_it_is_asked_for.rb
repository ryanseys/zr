# OpenSSL tier 1: versions, Digest, HMAC, KDF, Random, secure compares.
# Library version STRINGS are build-specific (zr vendors its own OpenSSL
# 3.x), so the golden prints shape checks, never the raw strings.
require "openssl"

puts "-- random + compares --"
p OpenSSL::Random.random_bytes(16).bytesize
p OpenSSL::Random.random_bytes(16).encoding
p OpenSSL.secure_compare("a" * 40, "a" * 40)
p OpenSSL.secure_compare("secret", "secreT")
p OpenSSL.fixed_length_secure_compare("abc", "abc")
begin
  OpenSSL.fixed_length_secure_compare("abc", "abcd")
rescue => e
  p [e.class, e.message]
end

