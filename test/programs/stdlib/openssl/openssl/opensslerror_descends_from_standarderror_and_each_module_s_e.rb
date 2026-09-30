# OpenSSL tier 1: versions, Digest, HMAC, KDF, Random, secure compares.
# Library version STRINGS are build-specific (zr vendors its own OpenSSL
# 3.x), so the golden prints shape checks, never the raw strings.
require "openssl"

puts "-- exception hierarchy --"
p OpenSSL::OpenSSLError.superclass
p OpenSSL::Digest::DigestError.superclass
p OpenSSL::BNError.superclass
p OpenSSL::Cipher::CipherError.superclass
p OpenSSL::Cipher::AuthTagError.superclass
p OpenSSL::SSL::SSLError.superclass
begin
  OpenSSL::Digest.new("NOPE")
rescue OpenSSL::OpenSSLError => e
  puts "caught as OpenSSLError"
end

