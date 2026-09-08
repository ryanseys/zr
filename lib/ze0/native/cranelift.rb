# frozen_string_literal: true

require "rbconfig"

module Ze0
  module Native
    # The Cranelift road: CLIF text and a data sidecar through the
    # `clif2obj` crate to a Mach-O object, then `cc` to a binary that links
    # libSystem and whatever archives the caller names. The crate is the
    # one piece of Rust in this repository, built on demand.
    class Cranelift
      attr_reader :root

      def initialize(root)
        @root = root
      end

      def crate
        File.join(@root, "clif2obj")
      end

      def binary
        File.join(crate, "target/release/clif2obj")
      end

      def available?
        File.executable?(binary)
      end

      # Build the crate. Cargo is the one tool this needs.
      def build!
        system("cargo", "build", "--release", "--quiet", chdir: crate) or raise "cargo build failed in #{crate}"
        binary
      end

      # `clif` and `data` (a sidecar path, or nil) to the object `obj`.
      # Answers nil, or the tool's message when it refused.
      def compile(clif, obj, data: nil)
        argv = [binary, clif, "-o", obj]
        argv.push("--data", data) if data
        log = IO.popen(argv, err: %i[child out], &:read)
        $?.success? ? nil : log.strip
      end

      # Link `objects` and `archives` into `out` with the system linker.
      def link(objects, out, archives: [], flags: [])
        argv = ["cc", "-o", out, *objects, *archives, *flags]
        log = IO.popen(argv, err: %i[child out], &:read)
        $?.success? ? nil : log.strip
      end
    end
  end
end
