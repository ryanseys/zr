# frozen_string_literal: true

module Zr
  module Harness
    # The host requirement for each `needs:` name. A program gives a
    # name in a program test's `foo.rb.needs` (test/support/program_case.rb).
    module Requirements
      # True when libssl 3 is where `require "openssl"` looks for it
      # (lib/zr/runtime/ext/openssl/ossl/library.rb). On macOS that is only
      # OPENSSL_DIR's lib when OPENSSL_DIR is set, else the Homebrew and
      # MacPorts prefixes. A glibc binary opens it on the host that runs
      # it, so the check runs there. A static musl binary and a wasm
      # module cannot open a library.
      def self.libssl?(runner)
        return glibc_libssl?(runner) if runner.target.libc == :glibc

        runner.platform == "macos" && macos_libssl?
      end

      # Whether this Mac has libssl 3 where a macOS binary looks for it.
      def self.macos_libssl?
        prefix = ENV.fetch("OPENSSL_DIR", "")
        dirs = prefix.empty? ? %w[/opt/homebrew/opt/openssl@3/lib /usr/local/opt/openssl@3/lib /opt/local/lib] : [File.join(prefix, "lib")]
        dirs.any? { |dir| File.exist?(File.join(dir, "libssl.3.dylib")) }
      end

      # Whether the host that runs the glibc target's binaries (through
      # `ZR_TEST_EXEC`, or this one) has libssl.so.3 in a directory that
      # the dynamic loader searches. One check for each target, which the
      # test threads share.
      GLIBC_LIBSSL = Hash.new
      GLIBC_LOCK = Mutex.new

      def self.glibc_libssl?(runner)
        GLIBC_LOCK.synchronize do
          GLIBC_LIBSSL.fetch(runner.target.triple) do |triple|
            dirs = ["/usr/lib/#{runner.target.arch}-linux-gnu", "/usr/lib64", "/usr/lib", "/usr/local/lib"]
            check = "for d in #{dirs.join(" ")}; do test -e $d/libssl.so.3 && exit 0; done; exit 1"
            GLIBC_LIBSSL[triple] = system(*runner.exec, "/bin/sh", "-c", check, out: File::NULL, err: File::NULL) == true
          end
        end
      end

      # True when the tests do not run as root, as on a developer machine:
      # root may change any id and chroot, so a test of what a user is
      # refused gives other answers (a container that runs as root).
      def self.nonroot?(_runner) = !Process.euid.zero?

      # True when the shell runs under any argv0, as the commands that
      # the tests start do on macOS and glibc systems. A busybox
      # multi-call binary (Alpine's sh and its other commands) picks what
      # it runs by argv0, so `["sh", "my-shell"]` finds nothing to run.
      def self.argv0?(_runner)
        sh = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, "sh") }.find { |path| File.executable?(path) }
        !sh.nil? && File.basename(File.realpath(sh)) != "busybox"
      end

      CHECKS = { "libssl" => method(:libssl?), "nonroot" => method(:nonroot?), "argv0" => method(:argv0?) }.freeze

      def self.met?(name, runner) = CHECKS.fetch(name).call(runner)
    end
  end
end
