# frozen_string_literal: true

module Ze0
  module Harness
    # One corpus program: the Ruby source above `__END__`, the `#@` header
    # directives, and ruby's recorded answer below. The recording is the
    # oracle: ruby 4.0.6 wrote it once, and nothing here re-runs ruby.
    #
    # The format is `docs/test-format.md`: a directive is a `#@ key: value`
    # line at column 0 above `__END__`; the trailer is stdout until a marker
    # line (`#@ stderr`, `#@ exit N`, `#@ signal N`, `#@ nonl`, and the
    # `#@ linux ...` forms, which record another platform's answer).
    # `code` is the exit status, `signal` the signal that killed it.
    Answer = Struct.new(:stdout, :stderr, :code, :signal) do
      def self.blank
        new(+"".b, +"".b, 0, nil)
      end

      def status
        signal ? "signal #{signal}" : "exit #{code}"
      end
    end

    Directives = Struct.new(:args, :stdin, :env, :ruby, :zeo, :zeo_env, :only, :backend, :gccheck) do
      def self.blank
        new([], nil, {}, [], [], {}, nil, nil, nil)
      end
    end

    class Case
      END_MARK = "__END__"
      KEYS = %w[args stdin env ruby zeo zeo-env only backend gccheck].freeze

      attr_reader :path, :program, :directives, :answer, :linux

      def self.read(path)
        new(File.binread(path), path)
      end

      def initialize(bytes, path = "(string)")
        @path = path
        program, trailer = split(bytes.b)
        @program = program
        @directives = parse_directives(program)
        @answer = nil
        @linux = nil
        parse_trailer(trailer) if trailer
      end

      # Whether ruby recorded an answer at all.
      def recorded?
        !@answer.nil?
      end

      # The answer for this machine. Only macOS runs anything here today.
      def expected
        @answer
      end

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
          when "zeo" then d.zeo = need.call.split
          when "zeo-env" then d.zeo_env = pairs(need.call, n)
          when "only"
            d.only = need.call
            raise ArgumentError, "#{@path}: line #{n}: unknown platform #{d.only.inspect}" unless %w[macos linux].include?(d.only)
          when "backend"
            d.backend = need.call
            raise ArgumentError, "#{@path}: line #{n}: `#@ backend: jit` is the only form" unless d.backend == "jit"
          when "gccheck" then d.gccheck = need.call
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
          linux, word, number = m
          if linux
            @linux ||= Answer.blank
            target = @linux
          else
            target = @answer
          end
          case word
          when "stdout", "stderr" then section = word.to_sym
          when "exit" then target.code = number
          when "signal" then target.signal = number
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
        linux = words.first == "linux"
        words.shift if linux
        word = words.shift
        case word
        when "stdout", "stderr" then [linux, word, nil]
        when "exit", "signal"
          n = Integer(words.first, exception: false)
          raise ArgumentError, "#{@path}: trailer marker `#{text}` needs a number" if n.nil?

          [linux, word, n]
        when "nonl"
          raise ArgumentError, "#{@path}: unknown trailer marker `#{text}`" if linux

          [false, word, nil]
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
