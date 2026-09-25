# frozen_string_literal: true

require_relative "../../../lib/zr/record"

module Zr
  module Harness
    # The output of a program: stdout, stderr, exit status and signal.
    class Answer < ::Zr::Record
      FIELDS = %i[stdout stderr code signal].freeze
      attr_accessor :stdout, :stderr, :code, :signal

      def initialize(stdout = nil, stderr = nil, code = nil, signal = nil)
        @stdout = stdout
        @stderr = stderr
        @code = code
        @signal = signal
      end

      def to_a = [@stdout, @stderr, @code, @signal]

      def self.blank
        new(+"".b, +"".b, 0, nil)
      end

      def status
        signal ? "signal #{signal}" : "exit #{code}"
      end

      # The recording of ruby's output for the program at `path`. It is
      # read from the files next to the program: always `<name>.out`, and
      # `<name>.err`, `<name>.status` and `<name>.signal` when they are
      # not empty. Each file contains only the raw bytes, so there is
      # nothing to parse or unescape. `zr-dev record` writes these files.
      # Returns nil when there is no recording.
      def self.beside(path)
        base = path.delete_suffix(".rb")
        return nil unless File.file?("#{base}.out")

        part = ->(kind) { File.file?("#{base}.#{kind}") ? File.binread("#{base}.#{kind}") : nil }
        new(File.binread("#{base}.out"), part.call("err") || +"".b,
            Integer(part.call("status") || 0), part.call("signal")&.then { |n| Integer(n) })
      end

      # A text that tells how `other` is different from this output.
      def apart_from(other)
        out = []
        %i[stdout stderr].each do |what|
          want, got = public_send(what).lines, other.public_send(what).lines
          next if want == got

          n = want.zip(got).index { |a, b| a != b }
          out << if n && n < [want.size, got.size].min
                   "#{what}: want #{want[n].chomp.inspect}, got #{got[n].chomp.inspect}"
                 else
                   "#{what}: want #{want.size} line(s), got #{got.size} -- #{(want[got.size] || got[want.size]).to_s.chomp.inspect}"
                 end
        end
        out << "#{status} vs #{other.status}" if status != other.status
        out.empty? ? "identical text, unequal bytes" : out.join("\n           ")
      end
    end

    # The host requirement for each `needs:` name. A program gives a
    # `needs:` name in `test/e2e/binaries_test.rb`.
    module Needs
      # True when libssl 3 is where `require "openssl"` looks for it
      # (runtime/ext/openssl/ossl/library.rb). That is only OPENSSL_DIR's
      # lib when OPENSSL_DIR is set, else the Homebrew and MacPorts
      # prefixes. Only a macOS binary opens a library. The linux and wasi
      # targets cannot.
      def self.libssl?(platform)
        return false unless platform == "macos"

        prefix = ENV.fetch("OPENSSL_DIR", "")
        dirs = prefix.empty? ? %w[/opt/homebrew/opt/openssl@3/lib /usr/local/opt/openssl@3/lib /opt/local/lib] : [File.join(prefix, "lib")]
        dirs.any? { |dir| File.exist?(File.join(dir, "libssl.3.dylib")) }
      end

      CHECKS = { "libssl" => method(:libssl?) }.freeze

      def self.met?(name, platform) = CHECKS.fetch(name).call(platform)
    end

    # Removes the parts of an output that change from run to run, so that
    # two outputs can be compared. It changes CRLF to LF, and the
    # program's absolute path to its path relative to the run directory.
    # It also removes the run directory and object addresses.
    module Normalize
      module_function

      # A process that a signal stopped has no exit status. Only the
      # signal counts.
      def answer(a, source, run_cwd)
        Answer.new(bytes(a.stdout, source, run_cwd), bytes(a.stderr, source, run_cwd), a.signal ? nil : a.code, a.signal)
      end

      def bytes(b, source, run_cwd)
        out = b.b.gsub("\r\n", "\n")
        abs = File.expand_path(source)
        cwd = File.expand_path(run_cwd)
        rel = abs.start_with?("#{cwd}/") ? abs.byteslice((cwd.bytesize + 1)..) : File.basename(abs)
        out = out.gsub(abs, rel)
        out = out.gsub("#{cwd}/", "")
        out.gsub(/0x[0-9a-f]+/) { |m| (8..16).cover?(m.bytesize - 2) ? "0xADDR" : m }
      end
    end
  end
end
