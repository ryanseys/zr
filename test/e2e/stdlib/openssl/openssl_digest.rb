# The vendored OpenSSL links: digests and HMAC come from it, not from the
# system library.
require "openssl"
puts OpenSSL::Digest::SHA256.hexdigest("zeo")
puts OpenSSL::HMAC.hexdigest("SHA256", "key", "message")
puts OpenSSL::Digest.new("SHA1").hexdigest("abc")
