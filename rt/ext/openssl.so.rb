# frozen_string_literal: true

# openssl.so: the C half of ruby's openssl gem (4.0.2), in Ruby over the
# host's own libssl and libcrypto 3, which `require "openssl"` opens
# (rt/ext/openssl/ossl/library.rb). Nothing cryptographic is done here:
# each method converts its arguments, calls the library as the C
# extension does, and raises what the C extension raises. The gem's
# Ruby half (vendor/ext/openssl/lib) stands on these classes as it
# stands on the C.
#
# The files under openssl/ossl each stand for the C file of the same
# name, and load in the order Init_openssl calls them.
require "digest"

require_relative "openssl/ossl/native"
require_relative "openssl/ossl/library"

module OpenSSL
  Lib.load
end

require_relative "openssl/ossl/ossl"
require_relative "openssl/ossl/digest"
require_relative "openssl/ossl/hmac"
require_relative "openssl/ossl/kdf"
require_relative "openssl/ossl/provider"
require_relative "openssl/ossl/rand"
require_relative "openssl/ossl/bn"
require_relative "openssl/ossl/cipher"
require_relative "openssl/ossl/bio"
require_relative "openssl/ossl/config"
require_relative "openssl/ossl/asn1"
