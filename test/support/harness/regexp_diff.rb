# frozen_string_literal: true

require "json"
require "strscan"
require_relative "onig_jit"

Zr.require_onig
require File.join(Zr::Paths::RUNTIME, "core/regexp_pattern.rb")

module Zr
  module Harness
    # Compares the Ruby Onigmo with ruby's own regexp engine, in one
    # process. A case is a pattern with its option bits, a subject, a byte
    # start and a mode (search, backward, at). Ruby compiles and matches it
    # as the reference. The core library compiles it and the kernel,
    # loaded with the JIT, matches it. The test compares the two results:
    # the error, the warnings, the position and the byte offsets of each
    # capture.
    module RegexpDiff
      IGNORECASE = 1
      EXTENDED = 2
      MULTILINE = 4
      FIXEDENCODING = 16
      NOENCODING = 32
      MODES = %w[search backward at].freeze
      LIMIT_NS = 2_000_000_000

      # An exception as the runner compares it: its class, its message
      # bytes, and the message encoding when the message is not ASCII.
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
        # bytes in hex. The encoding name is included when it is not UTF-8.
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

      # Ruby's result for a pattern: [:error, message] or
      # [:ok, regexp, warnings_quiet, warnings_verbose]. The warning texts
      # do not include the file prefix.
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

        # [position or nil, offsets] as the runner compares them. nil for no
        # match, [:error, text] for an error, or :timeout.
        def match(re, subject, start, mode)
          warnings(false) { match_quietly(re, subject, start, mode) }.first
        end

        def match_quietly(re, subject, start, mode)
          char_start = subject.byteslice(0, start).length
          if mode == "at" && (len = at_start(re, subject, start))
            # The captures come from a search. The search finds the same
            # match first, unless ruby's search optimizer skips it (its map
            # of case-folded bytes can miss a byte that folds to one of
            # them). In that case, only the length is known.
            md = re.match(subject, char_start)
            return [len, :elsewhere] unless md && md.byteoffset(0)[0] == start
          end
          md = case mode
               when "at" then len && md
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

        # onig_match at byte `start` over the whole subject, as
        # StringScanner#match? runs it with a fixed anchor. Returns the
        # length matched from `start` (to the end, including any text
        # before `\K`) or nil. A search from `start` then finds the same
        # match first.
        def at_start(re, subject, start)
          scanner = StringScanner.new(subject, fixed_anchor: true)
          scanner.pos = start
          scanner.match?(re)
        end

        # [block result, warnings]. It sets ruby's verbosity to `verbose`,
        # and collects each warning instead of printing it.
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

      # The result of the port. It runs the steps of Regexp.seat and
      # Regexp#program_for under host ruby (Regexp::Pattern and
      # Regexp::Onig, the same code that the runtime runs), and the
      # kernel's search under the JIT.
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

        # As Regexp#program_for: [program, reg] for the subject's encoding.
        # Each recompile changes the engine's encoding.
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

      # A case where ruby and the kernel give different results.
      Divergence = Struct.new(:kase, :what, :want, :got) do
        def to_s
          "DIFF #{kase.label}\n  #{what}\n  ruby:   #{want.inspect}\n  kernel: #{got.inspect}"
        end
      end

      class Runner
        attr_reader :divergences, :count, :timings, :slow

        def initialize(oracle: Oracle.new, candidate: Candidate.new, bench: false)
          @oracle = oracle
          @candidate = candidate
          @divergences = []
          @count = 0
          @bench = bench
          @timings = []
          @slow = []
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
          # Ruby used a large part of the time limit, and the slower kernel
          # went past it. This is a speed difference, not a wrong result.
          if actual == :timeout && expected != :timeout && t1 - t0 > LIMIT_NS / 8
            @slow << [kase, t1 - t0]
            return nil
          end
          actual[0] = nil if actual.is_a?(Array) && expected.is_a?(Array) && expected[0].nil?
          actual = [actual[0], :elsewhere] if actual.is_a?(Array) && actual[0] != :error && expected.is_a?(Array) && expected[1] == :elsewhere
          return nil if expected == actual

          diverge(kase, "match", expected, actual)
        end

        def diverge(kase, what, want, got)
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

      # The cases of one pattern, over the fixed subjects (unless `fixed`
      # is false) and the `extra` subjects. Each subject is searched from
      # the start and from the middle, searched backward from the end, and
      # matched at the start.
      def self.cases_for(pattern, options, extra = [], fixed: true)
        subjects = (fixed ? SUBJECTS + BINARY_SUBJECTS : []) + extra
        subjects.flat_map do |subject|
          # The character boundary nearest the middle. The start must be on
          # a boundary, because ruby changes a character index into bytes.
          half = subject.bytesize / 2
          mid = 0
          subject.each_char do |c|
            break if mid >= half

            mid += c.bytesize
          end
          rows = [Case.new(pattern, options, subject, 0, "search"), Case.new(pattern, options, subject, subject.bytesize, "backward"),
                  Case.new(pattern, options, subject, 0, "at")]
          rows << Case.new(pattern, options, subject, mid, "search") if mid > 0
          rows
        end
      end

      # The regexp literals, Regexp.new strings and string literals of a
      # Ruby file, found with prism: [[pattern, options], ...] and subjects.
      def self.harvest_file(path) = harvest(File.read(path))

      # The patterns and subjects in `source`, from its syntax tree.
      # `depth` limits the search into strings (see below).
      def self.harvest(source, depth = 0)
        require "prism"
        result = Prism.parse(source)
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
            # A spec contains the program that it compiles as a string, so
            # that program's patterns are inside a string. A string that is
            # long enough to be a program is parsed again. A string that is
            # not Ruby gives nothing, and costs one parse.
            patterns.concat(harvest(s, depth + 1).first) if depth.zero? && s.bytesize > 40 && s.include?("\n") && s.valid_encoding?
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

        # All encodings that ruby can read a pattern or subject in. The
        # encodings whose engine is most different from UTF-8 occur more often.
        ENCODINGS = (Encoding.list.reject(&:dummy?).map(&:name) +
                     %w[US-ASCII BINARY EUC-JP Windows-31J Shift_JIS ISO-8859-1 UTF-16LE UTF-16BE UTF-32LE UTF-32BE GB18030 Big5 EUC-TW CESU-8 Emacs-Mule]).freeze

        def subject
          alphabet = ["a", "b", "c", "x", " ", "\n", "1", "A", "é", "日", "ß", "K", "-", "_", "\t", "\u{1F600}", "あ", "ア", "Ａ", "ｱ", "Ω", "я", "Я", "ς", "Σ", "\u00FF", "\u0130", "ı", "中", "한"]
          (@rng.rand(12)).times.map { alphabet.sample(random: @rng) }.join
        end

        # Usually the String in UTF-8, else the String in another encoding
        # (see `carry`).
        def recode(s, pattern: false)
          return s if @rng.rand < (pattern ? 0.5 : 0.4)

          carry(s, Encoding.find(ENCODINGS.sample(random: @rng)))
        end

        # `s` in `encoding`. Usually it is converted, with "?" for a
        # character that the encoding does not have. Sometimes its bytes
        # stay the same and only the encoding label changes.
        def carry(s, encoding)
          return s.dup.force_encoding(encoding) if @rng.rand < 0.1

          s.encode(encoding, invalid: :replace, undef: :replace)
        rescue EncodingError
          s.dup.force_encoding(encoding)
        end

        def options
          [0, 0, 0, IGNORECASE, MULTILINE, EXTENDED, IGNORECASE | MULTILINE, NOENCODING, FIXEDENCODING, NOENCODING | IGNORECASE].sample(random: @rng)
        end

        def cases(count)
          out = []
          while out.size < count
            pat = recode(@rng.rand < 0.5 ? malformed : pattern, pattern: true)
            opts = options
            subjects = [recode(subject), recode(subject)]
            own = pat.encoding != Encoding::UTF_8
            if own
              alphabet_subjects = Array.new(4) { carry(subject, pat.encoding) }
              subjects.concat(alphabet_subjects)
            end
            RegexpDiff.cases_for(pat, opts, subjects, fixed: !own || @rng.rand < 0.2).each { |c| out << c }
          end
          out.first(count)
        end
      end

      # Makes valid patterns and subjects in one encoding at a time, from
      # characters of that encoding. Thus the engine's encoding data
      # (lengths, lead bytes, case folds, classes, properties, newlines)
      # meets text that it can match.
      class EncodingFuzz
        # One encoding of each encoder family in ruby, and some replicas.
        ENCODINGS = %w[
          US-ASCII ASCII-8BIT UTF-8 UTF8-MAC CESU-8 UTF-16LE UTF-16BE UTF-32LE UTF-32BE
          EUC-JP eucJP-ms CP51932 Shift_JIS Windows-31J MacJapanese SJIS-KDDI Big5 Big5-HKSCS CP950 GBK CP949 EUC-KR GB2312
          EUC-TW GB18030 Emacs-Mule stateless-ISO-2022-JP
          ISO-8859-1 ISO-8859-2 ISO-8859-3 ISO-8859-4 ISO-8859-5 ISO-8859-6 ISO-8859-7 ISO-8859-8 ISO-8859-9 ISO-8859-10
          ISO-8859-11 ISO-8859-13 ISO-8859-14 ISO-8859-15 ISO-8859-16 KOI8-R KOI8-U Windows-1250 Windows-1251 Windows-1252
          Windows-1253 Windows-1254 Windows-1257 Windows-1255 Windows-1256 TIS-620 IBM437 macRoman
        ].freeze

        # Characters to look for in each encoding: Latin letters and
        # their cases, the Latin-1 sharp s and dotted/dotless i, Greek,
        # Cyrillic, fullwidth and halfwidth forms, kana, CJK, Hangul and
        # a character past the BMP.
        UNICODE = ("ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿĀāĄąĆćČčĘęŁłŃńŒœŠšŸŽžİı" \
                   "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩαβγδεζηθικλμνξοπρσςτυφχψωΆάЁЂЃЄАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюяёђѓє" \
                   "ＡＢＣＺａｂｃｚ０１ｱｲｳﾝｰあいうえおかがアイウエオカガー日本語中文字漢字한국어가각" \
                   "×÷€™£¥§¶°±²³µ¼½¾¿¡«»" \
                   "\u{1F600}\u{10000}אבابกข").each_char.to_a.freeze
        ASCII = ["a", "b", "k", "s", "z", "A", "B", "K", "S", "Z", "0", "9", " ", "\n", "_", "-", ".", "/", "(", "\t"].freeze
        ATOMS = %w[. \\w \\W \\s \\S \\d \\h \\b \\B ^ $ \\A \\z \\Z \\G [[:alpha:]] [[:^alnum:]] [[:upper:]] [[:lower:]] [[:punct:]]
                   [[:print:]] [[:graph:]] [[:space:]] [[:word:]] [[:^word:]] \\R \\X \\p{Alpha} \\p{^Alpha} \\p{Hiragana} \\p{Katakana} \\p{Han}
                   \\p{Latin} \\p{Greek} \\p{Cyrillic} \\p{Word} \\p{Upper} \\1 \\k<n> (?i) (?-i) (?m) (?a) (?u) (?d)].freeze
        QUANTS = ["", "", "", "", "*", "+", "?", "{2}", "{1,3}", "*?", "+?", "?+", "{0,2}?"].freeze

        def initialize(seed)
          @rng = Random.new(seed)
          @repertoire = {}
        end

        # The characters of `enc` to build from: ASCII, the characters
        # that convert, and random byte sequences that ruby accepts as valid.
        def repertoire(enc)
          @repertoire[enc] ||= begin
            ascii = ASCII.map { |c| c.encode(enc) }
            wide = UNICODE.filter_map do |c|
              # A converter marks its output as valid without a check, so
              # the bytes are checked again in the encoding.
              s = c.encode(enc).b.force_encoding(enc)
              s.valid_encoding? && s.length == 1 ? s : nil
            rescue EncodingError
              nil
            end
            if wide.size < 12
              rng = Random.new(enc.name.sum)
              max = Regexp.const_get(:Pattern).mbmaxlen(enc)
              4000.times do
                len = 1 + rng.rand(max)
                s = Array.new(len) { rng.rand(256) }.pack("C*").force_encoding(enc)
                next unless s.valid_encoding? && s.length == 1 && !s.ascii_only?

                wide << s
                break if wide.size >= 40
              end
            end
            (ascii + wide.uniq).freeze
          end
        end

        def char(enc) = repertoire(enc).sample(random: @rng)

        # A character, escaped so that the pattern matches it literally.
        def literal(enc)
          c = char(enc)
          c.ascii_only? || c.encode("UTF-8", invalid: :replace, undef: :replace).match?(/\A[\w\p{L}]\z/) ? Regexp.escape(c) : c
        rescue EncodingError
          c
        end

        def syntax(text, enc) = text.encode(enc)

        def atom(enc, depth)
          case @rng.rand(10)
          when 0, 1, 2 then literal(enc)
          when 3, 4 then syntax(ATOMS.sample(random: @rng), enc)
          when 5
            a, b = [char(enc), char(enc)].sort_by(&:ord)
            s = syntax("[", enc)
            s << syntax("^", enc) if @rng.rand < 0.3
            s << Regexp.escape(a) << syntax("-", enc) << Regexp.escape(b) << literal(enc) << syntax("]", enc)
          when 6
            s = syntax("(?<=", enc) << literal(enc) << syntax(")", enc)
            s
          when 7, 8
            return literal(enc) if depth > 2

            open = ["(", "(?:", "(?<n>", "(?=", "(?!", "(?>", "(?i:", "(?<!"].sample(random: @rng)
            s = syntax(open, enc) << pattern(enc, depth + 1)
            s << syntax("|", enc) << pattern(enc, depth + 1) if @rng.rand < 0.3
            s << syntax(")", enc)
          else
            s = literal(enc) << literal(enc) << literal(enc)
            s
          end
        end

        def pattern(enc, depth = 0)
          out = String.new(encoding: enc)
          (1 + @rng.rand(4)).times { out << atom(enc, depth) << syntax(QUANTS.sample(random: @rng), enc) }
          out
        end

        def subject(enc)
          out = String.new(encoding: enc)
          @rng.rand(14).times { out << char(enc) }
          out
        end

        def options
          [0, 0, IGNORECASE, IGNORECASE, MULTILINE, IGNORECASE | MULTILINE, EXTENDED, FIXEDENCODING].sample(random: @rng)
        end

        # The cases of one pattern over subjects in its encoding. Each
        # subject is searched from each character boundary, searched
        # backward from the end and from the middle, and matched at the
        # start and at a random boundary.
        def cases(count)
          out = []
          while out.size < count
            enc = Encoding.find(ENCODINGS.sample(random: @rng))
            pat = pattern(enc)
            opts = options
            5.times do
              subj = subject(enc)
              bounds = [0]
              subj.each_char { |c| bounds << bounds.last + c.bytesize }
              bounds.each { |at| out << Case.new(pat, opts, subj, at, "search") }
              out << Case.new(pat, opts, subj, subj.bytesize, "backward")
              out << Case.new(pat, opts, subj, bounds[bounds.size / 2], "backward")
              out << Case.new(pat, opts, subj, 0, "at")
              out << Case.new(pat, opts, subj, bounds.sample(random: @rng), "at")
            end
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
