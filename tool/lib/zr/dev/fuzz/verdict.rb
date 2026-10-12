# frozen_string_literal: true

require "digest"

module Zr
  module Dev
    module Fuzz
      # What one program gives under ruby and as a zr binary, in one word
      # (`kind`) and a signature (`key`). Two failures with the same kind
      # and key are the same gap, so the fuzzer reduces and reports only
      # the first ones of each. The key leaves out what changes from case
      # to case: numbers, line numbers, quoted text and addresses.
      #
      # The kinds of a build: refused, internal-error, backend-refused,
      # build-crash, build-timeout and build-error. The kinds of a run:
      # same, timeout, memory, bug, crash, unimplemented, status-diff,
      # exception-diff and output-diff. `flaky` is given by the oracle,
      # when zr gives two answers for one program.
      Verdict = Struct.new(:kind, :key, :detail, keyword_init: true) do
        def same? = kind == "same"

        # The bucket of the verdict: the kind and a digest of the key, and
        # of the shape of the reduced case when one is given.
        def bucket(shape = nil)
          "#{kind}-#{Digest::SHA1.hexdigest([key, shape].compact.join("\0"))[0, 10]}"
        end

        def to_h = { kind: kind, key: key, detail: detail }
      end

      module Classify
        module_function

        # The kinds that mean zr is wrong only in a junk run: a refusal or
        # a difference in a run of junk is no fault.
        BUILD_FAULTS = %w[internal-error build-crash build-timeout bug crash].freeze

        # The verdict of `build` (a BuilderClient::Build, or nil when
        # the build was not tried), the answer of ruby, and the answer of
        # the binary (nil when the build failed). Answers are
        # Harness::Answer, normalized.
        def verdict(ruby, build, zr)
          return build_verdict(build) if build && !build.ok?

          run_verdict(ruby, zr)
        end

        def build_verdict(build)
          err = text(build.stderr)
          return Verdict.new(kind: "build-timeout", key: "", detail: "the build took longer than its limit") if build.timeout
          return Verdict.new(kind: "build-crash", key: "signal #{build.signal}", detail: first_line(err)) if build.signal

          if (form = err[/zr does not support (.+?) yet/, 1])
            return Verdict.new(kind: "refused", key: template(form), detail: "zr does not support #{form} yet")
          end
          if err.include?("a required file does not parse")
            return Verdict.new(kind: "refused", key: "a required file does not parse", detail: first_line(err))
          end
          if (m = err.match(/zr: internal error: (\S+?): (.*)/))
            return Verdict.new(kind: "internal-error", key: [m[1], *frames(err)].join(" "), detail: "#{m[1]}: #{m[2]}")
          end
          if (why = err[/zr cannot compile this program: (.*?)\. This is a limit/m, 1])
            return Verdict.new(kind: "backend-refused", key: template(why.split(":").first), detail: why)
          end

          Verdict.new(kind: "build-error", key: template(first_line(err)), detail: first_line(err))
        end

        def run_verdict(ruby, zr)
          return Verdict.new(kind: "same", key: "", detail: "") if parts(ruby) == parts(zr)
          return Verdict.new(kind: "timeout", key: "", detail: "zr ran longer than its limit") if zr.code == :timeout
          return Verdict.new(kind: "memory", key: "", detail: "zr used more memory than its limit") if zr.code == :memory

          err = text(zr.stderr)
          if (bug = err[/\[BUG\].*/])
            return Verdict.new(kind: "bug", key: template(bug), detail: bug)
          end
          return Verdict.new(kind: "crash", key: "signal #{zr.signal}", detail: first_line(err)) if zr.signal && !ruby.signal

          missing = (text(zr.stdout) + err)[/[\w:#.?!\[\]=<>+\-*\/]+ is not implemented yet/]
          if missing && !(text(ruby.stdout) + text(ruby.stderr)).include?(missing)
            return Verdict.new(kind: "unimplemented", key: missing, detail: missing)
          end
          if ruby.code != zr.code || ruby.signal != zr.signal
            return Verdict.new(kind: "status-diff", key: "#{status(ruby)} #{status(zr)}",
                               detail: "ruby #{status(ruby)}, zr #{status(zr)}")
          end
          if ruby.stderr != zr.stderr
            want, got = exception(text(ruby.stderr)), exception(text(zr.stderr))
            return Verdict.new(kind: "exception-diff", key: "#{want} | #{got}", detail: first_difference(ruby.stderr, zr.stderr))
          end

          want, got = differing_lines(ruby.stdout, zr.stdout)
          Verdict.new(kind: "output-diff", key: "#{template(want)} | #{template(got)}", detail: first_difference(ruby.stdout, zr.stdout))
        end

        def parts(answer) = [answer.stdout, answer.stderr, answer.code, answer.signal]

        def status(answer) = answer.signal ? "signal #{answer.signal}" : "exit #{answer.code}"

        # The text of bytes, with every bad byte as "?", so a regexp can
        # read it.
        def text(bytes) = bytes.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?")

        def first_line(text) = text.each_line.map(&:strip).find { |line| !line.empty? }.to_s

        # The first three of the compiler's own frames in a backtrace, as
        # "file#method", without line numbers.
        def frames(err)
          err.scan(%r{from (?:.*/)?(lib/zr/\S+?|zr/\S+?):\d+:in '([^']+)'}).first(3).map { |file, meth| "#{file}##{meth}" }
        end

        # The class and the message pattern of the exception in a report on
        # stderr ("file:1:in 'm': message (Class)"), or the first line.
        def exception(err)
          line = first_line(err)
          klass = line[/\(([A-Z]\w*(?:::[A-Z]\w*)*)\)\z/, 1]
          message = line.sub(/\A.*?:in '[^']*': /, "").sub(/ \([A-Z]\w*(?:::[A-Z]\w*)*\)\z/, "")
          klass ? "#{klass}: #{template(message)}" : template(line)
        end

        # The first line where `a` and `b` differ, from each.
        def differing_lines(a, b)
          want = text(a).lines
          got = text(b).lines
          n = (0...[want.size, got.size].max).find { |i| want[i] != got[i] } || 0
          [want[n].to_s.chomp, got[n].to_s.chomp]
        end

        def first_difference(a, b)
          want, got = differing_lines(a, b)
          "ruby #{want.inspect}, zr #{got.inspect}"
        end

        # `line` with what changes from case to case taken out: addresses,
        # quoted text, numbers. Long lines keep their start.
        def template(line)
          line.to_s
              .gsub(/0x(?:ADDR|\.\.\.|\h+)/, "ADDR")
              .gsub(/"(?:[^"\\]|\\.)*"/, '"Q"')
              .gsub(/'(?:[^'\\]|\\.)*'/, "'Q'")
              .gsub(/(?<!0x)(?<![\w.])-?\d+(?:\.\d+)?(?:e[+-]?\d+)?|(?<=[A-Za-z_])\d+/, "N")
              .gsub(/\s+/, " ")
              .strip[0, 160]
        end
      end
    end
  end
end
