# OpenSSL tier 1: versions, Digest, HMAC, KDF, Random, secure compares.
# Library version STRINGS are build-specific (zr vendors its own OpenSSL
# 3.x), so the golden prints shape checks, never the raw strings.
require "openssl"

puts "-- digest --"
d = OpenSSL::Digest.new("SHA256")
p d.class
p d.name
p d.hexdigest("abc")
d2 = OpenSSL::Digest::SHA256.new
d2 << "a"
d2.update("bc")
p d2.hexdigest
p d2.hexdigest # peek does not consume
p d2.digest.bytesize
p d2.digest_length
p d2.block_length
d2.reset
p d2.hexdigest == OpenSSL::Digest::SHA256.new.hexdigest
p OpenSSL::Digest::SHA256.hexdigest("abc")
p OpenSSL::Digest::SHA256.digest("abc").bytesize
p OpenSSL::Digest::SHA1.hexdigest("abc")
p OpenSSL::Digest::MD5.hexdigest("abc")
p OpenSSL::Digest.hexdigest("SHA1", "abc")
p OpenSSL::Digest.digest("MD5", "abc").bytesize
p OpenSSL::Digest.new("sha256").name
p OpenSSL::Digest::SHA256.new("abc").hexdigest
p [OpenSSL::Digest::MD5.new.digest_length, OpenSSL::Digest::SHA1.new.digest_length,
   OpenSSL::Digest::SHA384.new.digest_length, OpenSSL::Digest::SHA512.new.digest_length]
seeded = OpenSSL::Digest.new("SHA512", "hello ")
seeded << "world"
p seeded.hexdigest == OpenSSL::Digest::SHA512.hexdigest("hello world")
begin
  OpenSSL::Digest.new("NOPE")
rescue => e
  p e.class
  p e.class.ancestors.include?(OpenSSL::OpenSSLError)
end

