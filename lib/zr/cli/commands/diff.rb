# frozen_string_literal: true

require_relative "../../child_ruby"
require_relative "../command"
require_relative "../options"

module Zr
  module CLI
    module Commands
      # `zr diff [options] FILE [args...]`: runs FILE under ruby and as a zr
      # binary, and compares stdout, stderr, the exit status and the signal.
      # It prints the kind of difference (`Zr::Diff.kind`), and a diff of
      # each part. Exit status 0 when the two are the same, 1 when they
      # differ, 2 when the build broke, and 3 when zr refused the program.
      #
      # In `Commands`, `Diff` names this class: the runs are `Zr::Diff`.
      class Diff < Command
        #: (Array[String] argv) -> void
        def run(argv)
          require_relative "../../diff"
          words = argv.dup
          opts = Options.parse("run", words)
          usage_error("--emit does not apply; zr diff runs a binary for this host") if opts[:emit]
          input = opts[:input]
          Errors.file!(input)
          # `input` is one of the words, so `index` finds it.
          at = argv.index(input) #: Integer
          options = argv.take(at)
          Paths.tmpdir("zr-diff-") do |work|
            out = File.join(work, "program")
            built = Zr::Diff.run([RbConfig.ruby, File.join(Paths::ROOT, "exe/zr"), "build", *options, input, "-o", out], limit: nil)
            unless built.status.zero?
              puts built.status == REFUSED ? "refused" : "build-error"
              $stderr.print built.stderr
              exit(built.status == REFUSED ? REFUSED : 2)
            end
            # zr gives the pinned ruby's output, whatever ruby runs zr.
            unless RUBY_VERSION.start_with?(RUBY.split(".").first(2).join("."))
              warn "zr: note: zr diff compares with ruby #{RUBY_VERSION}, and zr gives ruby #{RUBY_PIN}'s output; " \
                   "some differences are ruby's own"
            end
            ruby = Zr::Diff.run([RbConfig.ruby, input, *opts[:args]], env: ruby_env)
            zr = Zr::Diff.run([out, *opts[:args]])
            kind = Zr::Diff.kind(ruby, zr)
            puts kind
            print Zr::Diff.report(ruby, zr)
            exit(kind == "same" ? 0 : 1)
          end
        end

        private

        # ruby reads the gems of the same environment as the build. With
        # BUNDLE_GEMFILE, it runs as `bundle exec ruby` does.
        #: () -> Hash[String, String?]
        def ruby_env
          gemfile = ENV["BUNDLE_GEMFILE"]
          env = ChildRuby::UNBUNDLED #: Hash[String, String?]
          return env if gemfile.to_s.empty?

          env.merge("BUNDLE_GEMFILE" => File.expand_path(gemfile), "RUBYOPT" => "-rbundler/setup")
        end
      end
    end
  end
end
