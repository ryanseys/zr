# OpenSSL tier 1: versions, Digest, HMAC, KDF, Random, secure compares.
# Library version STRINGS are build-specific (zr vendors its own OpenSSL
# 3.x), so the golden prints shape checks, never the raw strings.
require "openssl"

puts "-- versions --"
p OpenSSL::VERSION.match?(/\A\d+\.\d+\.\d+/)
p OpenSSL::OPENSSL_VERSION.start_with?("OpenSSL 3.")
p OpenSSL::OPENSSL_LIBRARY_VERSION.start_with?("OpenSSL 3.")
p OpenSSL::OPENSSL_VERSION_NUMBER >= 0x30000000

