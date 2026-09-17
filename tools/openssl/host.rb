# frozen_string_literal: true

# Runs the openssl port on ruby itself, in place of ruby's openssl
# extension:
#
#   ruby -r ./tools/openssl/host.rb program.rb
#
# `require "openssl"` then loads the gem's Ruby half as ze0 vendors it
# (vendor/ext/openssl/lib), and its `require "openssl.so"` loads
# rt/ext/openssl.so.rb over tools/openssl/native.rb, the Fiddle twin of
# the kernel's calls. A program sees the port where it would see the C.
root = File.expand_path("../..", __dir__)
$LOAD_PATH.unshift(File.join(root, "vendor/ext/openssl/lib"))

require_relative "native"
# The port's own require of its native reach is satisfied by the twin.
$LOADED_FEATURES << File.join(root, "rt/ext/openssl/ossl/native.rb")

module Ze0
  module OpenSSLHost
    PORT = File.join(File.expand_path("../..", __dir__), "rt/ext/openssl.so.rb")

    def require(name)
      return super unless name == "openssl.so"
      return false if $LOADED_FEATURES.include?(PORT)

      $LOADED_FEATURES << PORT
      load PORT
      true
    end
  end
end

Kernel.prepend(Ze0::OpenSSLHost)
