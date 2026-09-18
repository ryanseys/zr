# frozen_string_literal: true

module Ze0
  module Harness
    # What a program said, what the machine it runs on must have, and
    # the scrubs that let two answers be compared.
    Answer = Struct.new(:stdout, :stderr, :code, :signal) do
      def self.blank
        new(+"".b, +"".b, 0, nil)
      end

      def status
        signal ? "signal #{signal}" : "exit #{code}"
      end

      # What ruby answered for the program at `path`, read from the
      # files beside it: `<name>.out` always, and `<name>.err`,
      # `<name>.status` and `<name>.signal` when there is something to
      # say. Each holds those bytes and no others, so there is nothing
      # to parse and nothing to escape. `rake record` writes them, and
      # nil means nobody has yet.
      def self.beside(path)
        base = path.delete_suffix(".rb")
        return nil unless File.file?("#{base}.out")

        part = ->(kind) { File.file?("#{base}.#{kind}") ? File.binread("#{base}.#{kind}") : nil }
        new(File.binread("#{base}.out"), part.call("err") || +"".b,
            Integer(part.call("status") || 0), part.call("signal")&.then { |n| Integer(n) })
      end

      # The parts of `other` that part from these, in words.
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

    # What a `needs:` name asks of the machine that runs a program.
    # `test/e2e/binaries_test.rb` is where a program names one.
    module Needs
      # libssl 3 where `require "openssl"` looks for it
      # (rt/ext/openssl/ossl/library.rb): OPENSSL_DIR's lib alone when it
      # is set, else the Homebrew and MacPorts prefixes. Only a macOS
      # binary opens a library; the linux and wasi targets cannot.
      def self.libssl?(platform)
        return false unless platform == "macos"

        prefix = ENV.fetch("OPENSSL_DIR", "")
        dirs = prefix.empty? ? %w[/opt/homebrew/opt/openssl@3/lib /usr/local/opt/openssl@3/lib /opt/local/lib] : [File.join(prefix, "lib")]
        dirs.any? { |dir| File.exist?(File.join(dir, "libssl.3.dylib")) }
      end

      CHECKS = { "libssl" => method(:libssl?) }.freeze

      def self.met?(name, platform) = CHECKS.fetch(name).call(platform)
    end

    # The scrubs that make two answers comparable: CRLF, the program's
    # absolute path back to its run-directory-relative spelling, the run
    # directory itself, object addresses, panic thread ids.
    module Normalize
      module_function

      # A process a signal ended has no exit status: only the signal
      # counts.
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
        out = out.gsub(/0x[0-9a-f]+/) { |m| (8..16).cover?(m.bytesize - 2) ? "0xADDR" : m }
        out.gsub(/' \(\d+\)/, "' (TID)")
      end
    end
  end
end
