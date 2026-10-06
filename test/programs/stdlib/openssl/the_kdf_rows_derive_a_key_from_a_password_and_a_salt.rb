# OpenSSL tier 1: versions, Digest, HMAC, KDF, Random, secure compares.
# Library version STRINGS are build-specific (zr vendors its own OpenSSL
# 3.x), so the golden prints shape checks, never the raw strings.
require "openssl"

puts "-- kdf --"
p OpenSSL::KDF.pbkdf2_hmac("password", salt: "salt", iterations: 1000,
                           length: 32, hash: "SHA256").unpack1("H*")
p OpenSSL::KDF.pbkdf2_hmac("password", salt: "salt", iterations: 1,
                           length: 20, hash: OpenSSL::Digest.new("SHA1")).unpack1("H*")
p OpenSSL::KDF.hkdf("ikm", salt: "salt", info: "info", length: 32, hash: "SHA256").unpack1("H*")
p OpenSSL::KDF.hkdf("ikm", salt: "", info: "", length: 16, hash: "SHA256").unpack1("H*")
p OpenSSL::KDF.scrypt("password", salt: "salt", N: 1024, r: 8, p: 16, length: 16).unpack1("H*")
begin
  OpenSSL::KDF.pbkdf2_hmac("password", salt: "salt", iterations: 1000, length: 32)
rescue => e
  p [e.class, e.message]
end
p OpenSSL::KDF::KDFError.superclass
p OpenSSL::PKCS5.pbkdf2_hmac("password", "salt", 1000, 32, "SHA256") ==
  OpenSSL::KDF.pbkdf2_hmac("password", salt: "salt", iterations: 1000, length: 32, hash: "SHA256")

