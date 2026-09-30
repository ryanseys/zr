# OPENSSL_VERSION and OPENSSL_VERSION_NUMBER name the headers that ruby's
# openssl was built against, and OPENSSL_LIBRARY_VERSION the library.
require "openssl"
p OpenSSL::OPENSSL_VERSION.start_with?("OpenSSL 3"), OpenSSL::OPENSSL_VERSION_NUMBER >= 0x30000000
p OpenSSL::OPENSSL_LIBRARY_VERSION.start_with?("OpenSSL 3"), OpenSSL::OPENSSL_VERSION.encoding, OpenSSL::OPENSSL_VERSION.frozen?
p OpenSSL::OPENSSL_LIBRARY_VERSION.encoding
