# frozen_string_literal: true

module Ze0
  module Harness
    # One corpus program: the Ruby source above `__END__`, the `#@` header
    # directives, and ruby's recorded answer below. The recording is the
    # oracle: ruby 4.0.6 wrote it once, and nothing here re-runs ruby.
    #
    # The format is `docs/reference/test-format.md`: a directive is a `#@ key: value`
    # line at column 0 above `__END__`; the trailer is stdout until a marker
    # line (`#@ stderr`, `#@ exit N`, `#@ signal N`, `#@ nonl`, and the
    # `#@ linux ...` and `#@ wasi ...` forms, which record where another
    # platform's answer parts from macOS's). `code` is the exit status,
    # `signal` the signal that killed it.
    Answer = Struct.new(:stdout, :stderr, :code, :signal) do
      def self.blank
        new(+"".b, +"".b, 0, nil)
      end

      def status
        signal ? "signal #{signal}" : "exit #{code}"
      end
    end

    Directives = Struct.new(:args, :stdin, :env, :ruby, :zeo_env, :only, :needs, :build_mb, :skip) do
      def self.blank
        new([], nil, {}, [], {}, nil, [], nil, nil)
      end
    end

    # What a `#@ needs:` name asks of the machine that runs a program.
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

    class Case
      END_MARK = "__END__"
      KEYS = %w[args stdin env ruby zeo-env only needs build-mb skip].freeze
      # The platforms a recording answers for. macOS's sections carry no
      # prefix; every other platform's are the ones where its answer parts
      # from macOS's.
      PLATFORMS = %w[macos linux wasi].freeze
      PREFIXED = (PLATFORMS - ["macos"]).freeze

      attr_reader :path, :program, :directives, :answer

      def self.read(path)
        new(File.binread(path), path)
      end

      def initialize(bytes, path = "(string)")
        @path = path
        program, trailer = split(bytes.b)
        @program = program
        @directives = parse_directives(program)
        @answer = nil
        @others = {}
        parse_trailer(trailer) if trailer
      end

      # Whether ruby recorded an answer at all.
      def recorded?
        !@answer.nil?
      end

      # The answer on `platform`: each section that platform recorded,
      # and macOS's for the rest.
      def expected(platform = "macos")
        other, written = @others[platform]
        return @answer unless other

        status = written.include?(:status) ? other : @answer
        Answer.new(written.include?(:stdout) ? other.stdout : @answer.stdout,
                   written.include?(:stderr) ? other.stderr : @answer.stderr, status.code, status.signal)
      end

      # The sections `platform` recorded apart from macOS's: some of
      # :stdout, :stderr and :status.
      def sections(platform) = @others.fetch(platform, [nil, []]).last

      # Whether the program runs on `platform`: `#@ only:` names none, or
      # names it.
      def runs_on?(platform) = @directives.only.nil? || @directives.only.include?(platform)

      # The first `#@ needs:` name `platform` lacks, or nil.
      def unmet_need(platform) = @directives.needs.find { |name| !Needs.met?(name, platform) }

      private

      def split(bytes)
        at = 0
        while at <= bytes.bytesize
          rest = bytes.byteslice(at..)
          if rest.start_with?(END_MARK)
            after = rest.byteslice(END_MARK.bytesize..)
            return [bytes.byteslice(0, at), +"".b] if after.empty?
            return [bytes.byteslice(0, at), after.byteslice(1..)] if after.start_with?("\n")
          end
          nl = rest.index("\n")
          break if nl.nil?

          at += nl + 1
        end
        [bytes, nil]
      end

      def parse_directives(program)
        d = Directives.blank
        program.each_line.with_index(1) do |line, n|
          next unless line.start_with?("#@")

          rest = line.byteslice(2..).strip
          key, value = rest.split(":", 2).map(&:strip)
          need = -> { value or raise ArgumentError, "#{@path}: line #{n}: `#@ #{key}` needs a value" }
          case key
          when "args" then d.args = need.call.split
          when "stdin" then d.stdin = need.call
          when "env" then d.env = pairs(need.call, n)
          when "ruby" then d.ruby = need.call.split
          when "zeo-env" then d.zeo_env = pairs(need.call, n)
          when "only"
            d.only = need.call.split(/[\s,]+/)
            unknown = d.only - PLATFORMS
            raise ArgumentError, "#{@path}: line #{n}: unknown platform #{unknown.first.inspect}" unless unknown.empty?
          when "needs"
            d.needs = need.call.split(/[\s,]+/)
            unknown = d.needs - Needs::CHECKS.keys
            raise ArgumentError, "#{@path}: line #{n}: unknown need #{unknown.first.inspect}" unless unknown.empty?
          when "skip" then d.skip = need.call
          when "build-mb"
            d.build_mb = Integer(need.call, exception: false)
            raise ArgumentError, "#{@path}: line #{n}: `#@ build-mb` takes megabytes" unless d.build_mb&.positive?
          else
            raise ArgumentError, "#{@path}: line #{n}: unknown directive `#@ #{key}` (#{KEYS.join(", ")})"
          end
        end
        d
      end

      def pairs(value, n)
        value.split.to_h do |word|
          k, v = word.split("=", 2)
          raise ArgumentError, "#{@path}: line #{n}: #{word.inspect} is not KEY=VALUE" if v.nil?

          [k, v]
        end
      end

      def parse_trailer(bytes)
        @answer = Answer.blank
        target = @answer
        section = :stdout
        bytes.each_line do |line|
          text = line.chomp("\n")
          m = marker(text)
          if m.nil?
            body = target[section]
            body << unescape(text)
            body << "\n" if line.end_with?("\n")
            next
          end
          platform, word, number = m
          unless word == "nonl"
            written = nil
            target = @answer
            if platform
              target, written = @others[platform] ||= [Answer.blank, []]
            end
          end
          case word
          when "stdout", "stderr"
            section = word.to_sym
            written&.push(section)
          when "exit", "signal"
            target.code = word == "exit" ? number : nil
            target.signal = word == "signal" ? number : nil
            written&.push(:status)
          when "nonl"
            body = target[section]
            raise ArgumentError, "#{@path}: `#@ nonl` must follow a line" unless body.end_with?("\n")

            body.chop!
          end
        end
      end

      def marker(text)
        return nil unless text.start_with?("#@")

        words = text.byteslice(2..).split
        platform = words.shift if PREFIXED.include?(words.first)
        word = words.shift
        case word
        when "stdout", "stderr" then [platform, word, nil]
        when "exit", "signal"
          n = Integer(words.first, exception: false)
          raise ArgumentError, "#{@path}: trailer marker `#{text}` needs a number" if n.nil?

          [platform, word, n]
        when "nonl"
          raise ArgumentError, "#{@path}: unknown trailer marker `#{text}`" if platform

          [nil, word, nil]
        else
          raise ArgumentError, "#{@path}: unknown trailer marker `#{text}`"
        end
      end

      # The writer prefixed `#` to any body line that looked like a marker;
      # one comes back off.
      def unescape(line)
        line.match?(/\A##+@/) ? line.byteslice(1..) : line
      end
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
