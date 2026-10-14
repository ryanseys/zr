# frozen_string_literal: true

module Zr
  module Harness
    # The host requirement for each `needs:` name. A program gives a
    # name in a program test's `foo.rb.needs` (test/support/program_case.rb).
    module Requirements
      # True when libssl 3 is where `require "openssl"` looks for it
      # (lib/zr/runtime/ext/openssl/ossl/library.rb). That is only OPENSSL_DIR's
      # lib when OPENSSL_DIR is set, else the Homebrew and MacPorts
      # prefixes. Only a macOS binary opens a library. The linux and wasi
      # targets cannot.
      def self.libssl?(platform)
        return false unless platform == "macos"

        prefix = ENV.fetch("OPENSSL_DIR", "")
        dirs = prefix.empty? ? %w[/opt/homebrew/opt/openssl@3/lib /usr/local/opt/openssl@3/lib /opt/local/lib] : [File.join(prefix, "lib")]
        dirs.any? { |dir| File.exist?(File.join(dir, "libssl.3.dylib")) }
      end

      # True when the tests do not run as root, as on a developer machine:
      # root may change any id and chroot, so a test of what a user is
      # refused gives other answers (a container that runs as root).
      def self.nonroot?(_platform) = !Process.euid.zero?

      CHECKS = { "libssl" => method(:libssl?), "nonroot" => method(:nonroot?) }.freeze

      def self.met?(name, platform) = CHECKS.fetch(name).call(platform)
    end
  end
end
