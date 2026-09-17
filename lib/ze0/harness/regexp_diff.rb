# frozen_string_literal: true

require "json"
require "strscan"
require_relative "onig_jit"

Ze0::Zr.require_onig
require File.join(Ze0::Paths::RT, "core/regexp_pattern.rb")

module Ze0
  module Harness
    # The Ruby Onigmo held to ruby's own engine, in one process: a case
    # is a pattern with its option bits, a subject, a byte start and a
    # mode (search, backward, at); ruby compiles and matches it as the
    # oracle, the core compiles it and the JIT-loaded kernel matches it
    # as the candidate, and the two answers -- the error, the warnings,
    # the position and every capture's byte offsets -- are compared.
    module RegexpDiff
      IGNORECASE = 1
      EXTENDED = 2
      MULTILINE = 4
      FIXEDENCODING = 16
      NOENCODING = 32
      MODES = %w[search backward at].freeze
      LIMIT_NS = 2_000_000_000

      # An exception as the runner compares it: its class, its message bytes
      # and, past ASCII, the encoding the message is in.
      def self.shown_error(e)
        text = "#{e.class}: #{e.message.b.inspect[1..-2]}"
        e.message.ascii_only? ? text : "#{text} (#{e.message.encoding})"
      end

      Case = Struct.new(:pattern, :options, :subject, :start, :mode) do
        def to_h
          { **Case.text(pattern, "p"), "o" => options, **Case.text(subject, "s"), "at" => start, "m" => mode }
        end

        def self.from_h(h) = new(read(h, "p"), h["o"], read(h, "s"), h["at"], h["m"])

        # A String as JSON: its text when it is valid UTF-8, else its
        # bytes in hex, with its encoding named when it is not UTF-8.
        def self.text(s, key)
          utf8 = s.encoding == Encoding::UTF_8 && s.valid_encoding?
          { key => (utf8 ? s : nil), "#{key}b" => (utf8 ? nil : s.b.unpack1("H*")),
            "#{key}e" => (s.encoding == Encoding::UTF_8 ? nil : s.encoding.name) }.compact
        end

        def self.read(h, key)
          encoding = Encoding.find(h["#{key}e"] || "UTF-8")
          (h["#{key}b"] ? [h["#{key}b"]].pack("H*") : h[key].dup).force_encoding(encoding)
        end

        def flags = "#{(options & MULTILINE != 0 ? 'm' : '')}#{(options & IGNORECASE != 0 ? 'i' : '')}#{(options & EXTENDED != 0 ? 'x' : '')}"

        def label
          shown = ->(s) { s.encoding == Encoding::UTF_8 ? "" : " (#{s.encoding})" }
          "/#{pattern.b.inspect[1..-2]}/#{flags}#{shown.(pattern)}#{options & (FIXEDENCODING | NOENCODING) != 0 ? " o=#{options}" : ""} " \
            "#{mode}@#{start} on #{subject.inspect}#{shown.(subject)}"
        end
      end

      # What ruby answers for a pattern: [:error, message] or
      # [:ok, warnings_quiet, warnings_verbose], the warning texts with
      # the file prefix dropped.
      class Oracle
        def initialize
          @compiled = {}
        end

        def compile(pattern, options)
          @compiled[[pattern, options]] ||= begin
            _, quiet = warnings(false) { Regexp.new(pattern, options) }
            re, verbose = warnings(true) { Regexp.new(pattern, options) }
            [:ok, re, quiet, verbose]
          rescue RegexpError, ArgumentError, TypeError, Encoding::CompatibilityError => e
            [:error, RegexpDiff.shown_error(e)]
          end
        end

        # [position or nil, offsets] as tools/regexp_diff.rb compares them,
        # nil for no match, [:error, text] for a refusal, :timeout.
        def match(re, subject, start, mode)
          warnings(false) { match_quietly(re, subject, start, mode) }.first
        end

        def match_quietly(re, subject, start, mode)
          char_start = subject.byteslice(0, start).length
          md = case mode
               when "at" then at_start(re, subject, start) && re.match(subject, char_start)
               when "backward" then subject.rindex(re, char_start) && Regexp.last_match
               else re.match(subject, char_start)
               end
          return nil unless md

          offsets = (0...md.size).flat_map { |i| md.begin(i) ? md.byteoffset(i) : [-1, -1] }
          pos = if mode == "at"
                  at_start(re, subject, start)
                elsif mode == "search" && start == 0 && (i = subject =~ re)
                  subject[0, i].bytesize
                end
          [pos, offsets]
        rescue Regexp::TimeoutError
          :timeout
        rescue ArgumentError, Encoding::CompatibilityError, TypeError => e
          [:error, RegexpDiff.shown_error(e)]
        end

        private

        # onig_match at byte `start`, as StringScanner#match? runs it: the
        # length matched from `start` (to the end, past any `\K`) or nil.
        # A search from `start` then finds that same match first.
        def at_start(re, subject, start)
          scanner = StringScanner.new(subject)
          scanner.pos = start
          scanner.match?(re)
        end

        # [what the block answers, the warnings it gave] with ruby's
        # verbosity set as asked and every warning taken instead of printed.
        def warnings(verbose)
          out = []
          was = $VERBOSE
          $VERBOSE = verbose
          Warning.singleton_class.class_eval do
            alias_method :warn_before_diff, :warn
            define_method(:warn) { |message, **| out << message }
          end
          answer = yield
          [answer, out.map { |m| m.sub(/\A[^:]*:\d+: warning: /, "").chomp }]
        ensure
          Warning.singleton_class.class_eval do
            alias_method :warn, :warn_before_diff
            remove_method :warn_before_diff
          end
          $VERBOSE = was
        end
      end

      # What the port answers: Regexp.seat's and Regexp#program_for's
      # steps under host ruby (Regexp::Pattern and Regexp::Onig, the
      # same code the runtime runs) and the kernel's search under the JIT.
      class Candidate
        Compiled = Struct.new(:source, :program, :programs, :reg, :encoding, :quiet, :verbose, :options)

        def initialize(jit = OnigJIT.new)
          @jit = jit
          @compiled = {}
          @pattern = Regexp.const_get(:Pattern)
          @onig = Regexp::Onig
        end

        attr_reader :jit

        def compile(pattern, options)
          @compiled[[pattern, options]] ||= begin
            source = pattern.dup.freeze
            encoding, bits, reg, warnings = @pattern.compile(source, options)
            source = source.dup.force_encoding(encoding).freeze unless source.encoding == encoding
            rows = warnings.rows.map { |row| [row.text, row.verbose] }
            quiet = rows.reject { |_, v| v }.map(&:first)
            verbose = rows.map(&:first)
            [:ok, Compiled.new(source, @jit.program(reg), {}, reg, encoding, quiet, verbose, bits)]
          rescue RegexpError, ArgumentError, TypeError => e
            [:error, RegexpDiff.shown_error(e)]
          end
        end

        def match(compiled, subject, start, mode)
          program, reg = program_for(compiled, subject)
          r = @jit.search(program, reg.num_mem, subject, start: start, backward: mode == "backward", at: mode == "at", limit: LIMIT_NS)
          return :timeout if r == [:error, OnigJIT::TIMEOUT]
          return r if r.nil? || r[0] == :error

          pos = if mode == "at" then r[0]
                elsif mode == "search" && start == 0 then r[0]
                end
          [pos, r[1]]
        rescue ArgumentError, RegexpError, Encoding::CompatibilityError => e
          [:error, RegexpDiff.shown_error(e)]
        end

        private

        # Regexp#program_for: [program, reg] for the subject's encoding,
        # the engine's encoding moving with each compile again.
        def program_for(compiled, subject)
          raise ArgumentError, "invalid byte sequence in #{subject.encoding}" unless subject.ascii_only? || subject.valid_encoding?

          engine = compiled.programs.fetch(:engine, compiled.encoding)
          unless engine == subject.encoding || (subject.ascii_only? && engine == Encoding::US_ASCII)
            enc, = @pattern.prepared_encoding(engine, compiled.encoding, compiled.options, subject.encoding, subject.ascii_only?)
            unless enc == engine || enc == compiled.encoding
              entry = compiled.programs[enc] ||= begin
                reg, = @pattern.recompile(compiled.source, compiled.options, compiled.encoding, enc)
                [@jit.program(reg), reg]
              rescue ArgumentError, RegexpError => e
                e
              end
              raise entry.class, entry.message if entry.is_a?(Exception)
            end
            engine = compiled.programs[:engine] = enc
          end
          engine == compiled.encoding ? [compiled.program, compiled.reg] : compiled.programs[engine]
        end
      end

      # A case whose pattern or subject holds characters of an encoding
      # the port has no Onigmo encoder for (it reads them bytewise, as
      # the ASCII engine) or a property of one: a known gap, counted apart.
      def self.unported?(kase)
        ported = ->(e) { Regexp.const_get(:Pattern)::WIDE.include?(e.name) || e == Encoding::US_ASCII || e == Encoding::BINARY }
        # A property fixes the pattern to its encoding, whose tables name it.
        return true if !ported.(kase.pattern.encoding) && kase.pattern.b.match?(/\\[pP]/)

        [kase.pattern, kase.subject].any? { |s| !s.ascii_only? && !ported.(s.encoding) }
      end

      # One case compared: nil when the two agree, else a Divergence.
      Divergence = Struct.new(:kase, :what, :want, :got) do
        def to_s
          "DIFF #{kase.label}\n  #{what}\n  ruby:   #{want.inspect}\n  kernel: #{got.inspect}"
        end
      end

      class Runner
        attr_reader :divergences, :count, :timings, :slow, :unported

        def initialize(oracle: Oracle.new, candidate: Candidate.new, bench: false)
          @oracle = oracle
          @candidate = candidate
          @divergences = []
          @count = 0
          @bench = bench
          @timings = []
          @slow = []
          @unported = []
          @seen = {}
        end

        def run(kase)
          @count += 1
          want = @oracle.compile(kase.pattern, kase.options)
          got = @candidate.compile(kase.pattern, kase.options)
          if want[0] == :error || got[0] == :error
            return diverge(kase, "compile", want[0] == :error ? want[1] : "ok", got[0] == :error ? got[1] : "ok") if want[0] != got[0] || want[1] != got[1]

            return nil
          end
          unless @seen[[kase.pattern, kase.options]]
            @seen[[kase.pattern, kase.options]] = true
            return diverge(kase, "warnings", want[2], got.last.quiet) if want[2] != got.last.quiet
            return diverge(kase, "warnings (verbose)", want[3], got.last.verbose) if want[3] != got.last.verbose
          end
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
          expected = @oracle.match(want[1], kase.subject, kase.start, kase.mode)
          t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
          actual = @candidate.match(got[1], kase.subject, kase.start, kase.mode)
          t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
          @timings << [t2 - t1, t1 - t0, kase] if @bench
          # A match ruby itself spends a good part of the limit on, which
          # the slower kernel runs past: a speed gap, not a wrong answer.
          if actual == :timeout && expected != :timeout && t1 - t0 > LIMIT_NS / 8
            @slow << [kase, t1 - t0]
            return nil
          end
          actual[0] = nil if actual.is_a?(Array) && expected.is_a?(Array) && expected[0].nil?
          return nil if expected == actual

          diverge(kase, "match", expected, actual)
        end

        def diverge(kase, what, want, got)
          if RegexpDiff.unported?(kase)
            @unported << kase
            return nil
          end

          d = Divergence.new(kase, what, want, got)
          @divergences << d
          d
        end
      end

      # ---- cases ---------------------------------------------------------

      SUBJECTS = [
        "", "a", "abc", "aaa", "ab", "hello world", "The quick brown fox jumps over the lazy dog", "ab\ncd\n",
        "foo_bar-baz 42", "  spaces  ", "line1\nline2\nline3", "CamelCaseWord", "a.b*c+d?e|f", "123 456.78 -9",
        "日本語テキスト", "héllo wörld", "ΑΒΓ αβγ", "über straße", "\u{1F600}x\u{1F601}", "áb", "Kk",
        "xxABCxx", "AbCdEf", "tab\there", "\r\n", "a\r\nb\rc\nd", "!@\#$%^&*()", "[]{}()<>", "\\backslash\\",
        "ssß", "ǅǆ", "ⅰⅱⅲ", "🇯🇵🇺🇸", "a‍b", " nul ",
      ].map { |s| s.dup.force_encoding(Encoding::UTF_8).freeze }.freeze
      BINARY_SUBJECTS = ["\xFF\xFEab".b, "abc\xE9".b, "\xE3\x81\x82".b, "plain".b].map(&:freeze).freeze

      # The cases of one pattern: the fixed subjects and `extra` ones,
      # each searched from the start and from the middle, searched
      # backward from the end and matched at the start.
      def self.cases_for(pattern, options, extra = [])
        subjects = SUBJECTS + BINARY_SUBJECTS + extra
        subjects.flat_map do |subject|
          mid = subject.bytesize / 2
          mid += 1 while mid < subject.bytesize && !subject.byteslice(mid, 1).force_encoding(subject.encoding).valid_encoding?
          rows = [Case.new(pattern, options, subject, 0, "search"), Case.new(pattern, options, subject, subject.bytesize, "backward"),
                  Case.new(pattern, options, subject, 0, "at")]
          rows << Case.new(pattern, options, subject, mid, "search") if mid > 0
          rows
        end
      end

      # The regexp literals, Regexp.new strings and string literals of a
      # Ruby file, through prism: [[pattern, options], ...] and subjects.
      def self.harvest_file(path)
        require "prism"
        result = Prism.parse(File.read(path))
        patterns = []
        subjects = []
        queue = [result.value]
        until queue.empty?
          node = queue.shift
          case node
          when Prism::RegularExpressionNode
            options = 0
            options |= IGNORECASE if node.ignore_case?
            options |= EXTENDED if node.extended?
            options |= MULTILINE if node.multi_line?
            options |= NOENCODING if node.ascii_8bit?
            options |= FIXEDENCODING if node.utf_8?
            patterns << [node.content, options]
          when Prism::StringNode
            s = node.unescaped
            subjects << s if s.bytesize.between?(1, 120) && s.valid_encoding?
          when Prism::CallNode
            if node.name == :new && node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Regexp && node.arguments
              first, second = node.arguments.arguments
              if first.is_a?(Prism::StringNode)
                options = case second
                          when Prism::IntegerNode then second.value & 63
                          when Prism::StringNode then second.unescaped.each_char.sum { |c| { "i" => 1, "x" => 2, "m" => 4 }[c] || 0 }
                          when Prism::TrueNode then 1
                          else 0
                          end
                patterns << [first.unescaped, options]
              end
            end
          end
          queue.concat(node.compact_child_nodes)
        end
        [patterns.uniq, subjects.uniq.first(12)]
      rescue Prism::ParseError, ArgumentError
        [[], []]
      end

      # ---- fuzz ----------------------------------------------------------

      class Fuzz
        ATOMS = ["a", "b", "c", "x", ".", "\\w", "\\W", "\\d", "\\D", "\\s", "\\S", "\\h", "\\b", "\\B", "\\n", "\\t", "\\x41", "\\u3042",
                 "[a-c]", "[^a]", "[[:alpha:]]", "[[:^digit:]]", "[a-z&&[^aeiou]]", "\\p{L}", "\\p{^Alpha}", "\\P{Digit}", "\\p{Hiragana}",
                 "\\R", "\\X", "\\K", "^", "$", "\\A", "\\z", "\\Z", "\\G", "é", "日", "\u{1F600}", "ß", "K", "\\/", "\\.", "\\-", "\\\\",
                 "[\w-]", "[\s\S]", "[a-]", "[]a]", "[^]a]", "\1", "\2", "\k<n>", "\k<m>", "\g<n>", "\g<1>", "(?i)", "(?m)", "(?x)", "(?a)", "(?u)", "(?d)",
                 # the escapes ruby decodes before the engine reads the text
                 "\xff", "\xE3\x81\x82", "\xE3\x81", "\xA4\xA2", "\x82\xA0", "\M-a", "\C-a", "\c\M-a", "\M-\C-x", "\0", "\101",
                 "\377", "\u{61 62}", "\u00e9", "\u{1F600}", "(?#é)", "(?#a\)b)", "# c\n", "[\xe9]", "\p{Alpha}"].freeze
        QUANTS = ["", "", "", "*", "+", "?", "{2}", "{1,3}", "{2,}", "{,2}", "*?", "+?", "??", "*+", "++", "?+", "{0}", "{1000}"].freeze
        OPENERS = ["(", "(?:", "(?<n>", "(?<m>", "(?=", "(?!", "(?<=", "(?<!", "(?>", "(?~", "(?i:", "(?m:", "(?x:", "(?-i:", "(?a:", "(?u:", "(?<n+1>", "(?(1)", "(?(<n>)"].freeze
        JUNK = ["(", ")", "[", "]", "{", "}", "*", "+", "?", "\\", "|", "-", "&&", "{1,", "\\k<", "(?<", "\\p{", "\\x", "\\u{", "\\c", "\\M-", "[:alpha:]", "(?#c)", "(?", "\\g<", "a{2,1}", "\\p{Foo}", "(?<1>a)", "\\0", "\\99"].freeze

        def initialize(seed)
          @rng = Random.new(seed)
        end

        def pattern(depth = 0)
          parts = (1 + @rng.rand(4)).times.map { term(depth) }
          out = parts.join
          out = "#{out}|#{pattern(depth + 1)}" if depth < 2 && @rng.rand < 0.2
          out
        end

        def term(depth)
          body = if depth < 3 && @rng.rand < 0.3
                   "#{OPENERS.sample(random: @rng)}#{pattern(depth + 1)})"
                 else
                   ATOMS.sample(random: @rng)
                 end
          "#{body}#{QUANTS.sample(random: @rng)}"
        end

        def malformed
          p = pattern
          case @rng.rand(3)
          when 0 then p.dup.tap { |s| s.slice!(@rng.rand(s.size)) if s.size > 1 }
          when 1 then p.dup.insert(@rng.rand(p.size + 1), JUNK.sample(random: @rng))
          else "#{JUNK.sample(random: @rng)}#{p}"
          end
        end

        ENCODINGS = %w[US-ASCII BINARY EUC-JP Windows-31J ISO-8859-1 UTF-16LE].freeze
        # The engine reads ASCII-compatible patterns only (the port carries
        # Onigmo's UTF-8 and ASCII encoders).
        PATTERN_ENCODINGS = (ENCODINGS - %w[UTF-16LE]).freeze

        def subject
          alphabet = ["a", "b", "c", "x", " ", "\n", "1", "A", "é", "日", "ß", "K", "-", "_", "\t", "\u{1F600}"]
          recode((@rng.rand(12)).times.map { alphabet.sample(random: @rng) }.join)
        end

        # A String in UTF-8 most of the time, else carried to another
        # encoding: converted where it can be, its bytes relabeled where not.
        def recode(s, pattern: false)
          return s if @rng.rand < 0.7

          encoding = Encoding.find((pattern ? PATTERN_ENCODINGS : ENCODINGS).sample(random: @rng))
          begin
            s.encode(encoding)
          rescue EncodingError
            s.dup.force_encoding(encoding)
          end
        end

        def options
          [0, 0, 0, IGNORECASE, MULTILINE, EXTENDED, IGNORECASE | MULTILINE, NOENCODING, FIXEDENCODING, NOENCODING | IGNORECASE].sample(random: @rng)
        end

        def cases(count)
          out = []
          while out.size < count
            pat = recode(@rng.rand < 0.5 ? malformed : pattern, pattern: true)
            opts = options
            subjects = [subject, subject]
            RegexpDiff.cases_for(pat, opts, subjects).each { |c| out << c }
          end
          out.first(count)
        end
      end

      # ---- io ------------------------------------------------------------

      def self.write_jsonl(path, cases)
        File.open(path, "w") { |f| cases.each { |c| f.puts JSON.generate(c.to_h) } }
      end

      def self.read_jsonl(path)
        File.foreach(path).map { |line| Case.from_h(JSON.parse(line)) }
      end
    end
  end
end
