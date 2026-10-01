# frozen_string_literal: true

require_relative "../command"
require_relative "../options"

module Zr
  module CLI
    module Commands
      # `zr diff [options] FILE [args...]`: runs FILE under ruby and as a zr
      # binary, and compares stdout, stderr, the exit status and the signal.
      # It prints the kind of difference (`Zr::Diff.kind`), and a diff of
      # each part. Exit status 0 when the two are the same, else 1.
      #
      # In `Commands`, `Diff` names this class: the runs are `Zr::Diff`.
      class Diff < Command
        def run(argv)
          require_relative "../../diff"
          words = argv.dup
          opts = Options.parse("run", words)
          usage_error("--emit does not apply; zr diff runs a binary for this host") if opts[:emit]
          input = opts[:input]
          abort "zr: no such file: #{input}" unless File.file?(input)
          options = argv.take(argv.index(input))
          gem_set = Options.gem_set(opts)
          Paths.tmpdir("zr-diff-") do |work|
            out = File.join(work, "program")
            built = Zr::Diff.run([RbConfig.ruby, File.join(Paths::ROOT, "exe/zr"), "build", *options, input, "-o", out], limit: nil)
            unless built.status.zero?
              puts built.status == REFUSED ? "refused" : "build-error"
              $stderr.print built.stderr
              exit 1
            end
            ruby = Zr::Diff.run([RbConfig.ruby, *ruby_flags(gem_set), input, *opts[:args]], env: ruby_env(opts))
            zr = Zr::Diff.run([out, *opts[:args]])
            kind = Zr::Diff.kind(ruby, zr)
            puts kind
            print Zr::Diff.report(ruby, zr)
            exit(kind == "same" ? 0 : 1)
          end
        end

        private

        # ruby reads the same `--gem` roots that the build read.
        def ruby_flags(gem_set)
          gem_set.gems.reject(&:refusal).flat_map(&:roots).flat_map { |root| ["-I", root] }
        end

        # With a Gemfile, ruby runs as `bundle exec ruby` does.
        def ruby_env(opts)
          gemfile = opts[:gemfile] || ENV["BUNDLE_GEMFILE"]
          env = { "RUBYOPT" => nil, "BUNDLER_SETUP" => nil }
          return env if gemfile.to_s.empty?

          env.merge("BUNDLE_GEMFILE" => File.expand_path(gemfile), "RUBYOPT" => "-rbundler/setup")
        end
      end
    end
  end
end
