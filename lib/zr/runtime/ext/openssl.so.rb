# frozen_string_literal: true

Object.send(:native_module, :OpenSSL)

# openssl.so: the C part of ruby's openssl gem (4.0.2), in Ruby over the
# host's own libssl and libcrypto 3, which `require "openssl"` opens
# (lib/zr/runtime/ext/openssl/ossl/library.rb). Nothing cryptographic is done here:
# each method converts its arguments, calls the library as the C
# extension does, and raises what the C extension raises. The gem's
# Ruby part (openssl/, vendored in vendor/ruby) uses these classes as it uses
# the C.
#
# The files under openssl/ossl each represent the C file of the same
# name, and load in the order in which Init_openssl calls them.
require "digest"

require_relative "openssl/ossl/native"
require_relative "openssl/ossl/library"

module OpenSSL
  Lib.load
end

require_relative "openssl/ossl/ossl"
require_relative "openssl/ossl/digest"
require_relative "openssl/ossl/hmac"
require_relative "openssl/ossl/hpke"
require_relative "openssl/ossl/kdf"
require_relative "openssl/ossl/provider"
require_relative "openssl/ossl/rand"
require_relative "openssl/ossl/bn"
require_relative "openssl/ossl/cipher"
require_relative "openssl/ossl/bio"
require_relative "openssl/ossl/config"
require_relative "openssl/ossl/asn1"
require_relative "openssl/ossl/pkey"
require_relative "openssl/ossl/pkey_rsa"
require_relative "openssl/ossl/pkey_dsa"
require_relative "openssl/ossl/pkey_dh"
require_relative "openssl/ossl/pkey_ec"
require_relative "openssl/ossl/x509"
require_relative "openssl/ossl/x509attr"
require_relative "openssl/ossl/x509cert"
require_relative "openssl/ossl/x509crl"
require_relative "openssl/ossl/x509ext"
require_relative "openssl/ossl/x509name"
require_relative "openssl/ossl/x509req"
require_relative "openssl/ossl/x509revoked"
require_relative "openssl/ossl/x509store"
require_relative "openssl/ossl/ssl_session"
require_relative "openssl/ossl/ssl"
require_relative "openssl/ossl/pkcs7"
require_relative "openssl/ossl/pkcs12"
require_relative "openssl/ossl/ns_spki"
require_relative "openssl/ossl/ocsp"
require_relative "openssl/ossl/ts"
require_relative "openssl/ossl/constants"
