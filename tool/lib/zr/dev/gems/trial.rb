# frozen_string_literal: true

require "fileutils"
require_relative "../../../../../lib/zr/diff"
require_relative "../../../../../test/support/harness/child"
require_relative "../../../../../test/support/harness/reference"

module Zr
  module Dev
    module Gems
      # Tries one gem. It finds the gem and its dependencies, refuses what
      # zr cannot compile, and builds a probe: a program that requires the
      # gem and prints each constant that the require defines. It runs the
      # probe under ruby 4.0.7 (the reference, with each gem's roots on
      # -I) and as a zr binary, and compares the two. An override with a
      # smoke program (gems/<name>.rb) runs the same way.
      #
      #   refused   zr refuses the gem, or a form in it
      #   fails     the build fails
      #   compiles  the binary runs, and its output is not ruby's
      #   loads     the probe gives ruby's output
      #   verified  the smoke program gives ruby's output too
      #   skipped   an override skips the gem, or ruby itself fails
      #
      # Each child has a time and a memory limit. The work directory is
      # removed after the trial, unless `keep`. The full log goes to
      # `logs/<name>-<version>.txt`.
      class Trial
        BUILD_SECONDS = 600
        RUN_SECONDS = 60
        # zr's exit status for a refusal (Zr::CLI::REFUSED).
        REFUSED = 3

        PROBE = <<~'RUBY'
          before = Object.constants
          REQUIRES
          (Object.constants - before).sort.each do |name|
            mod = Object.const_get(name)
            puts "#{name} #{mod.class}"
            next unless mod.is_a?(Module)

            puts "  VERSION #{mod::VERSION}" if mod.const_defined?(:VERSION, false)
            puts "  #{mod.constants(false).sort.join(" ")}"
          end
        RUBY

        # The probe program for `features`.
        def self.probe(features) = PROBE.sub("REQUIRES", features.map { |feature| "require #{feature.dump}" }.join("\n"))

        # Runs a child with Harness::Child's limits. A test gives a runner
        # of its own.
        class Runner
          # `[Zr::Diff::Answer, limit]`: the limit is :timeout or :memory
          # when one stopped the child, else nil.
          def run(argv, dir:, seconds:, megabytes:, env: {})
            answer, = Harness::Child.run(argv, cwd: dir, env: env, seconds: seconds, megabytes: megabytes)
            limit = answer.code if answer.code.is_a?(Symbol)
            [Diff::Answer.new(Diff.unaddressed(answer.stdout), Diff.unaddressed(answer.stderr), limit ? nil : answer.code,
                              answer.signal, limit == :timeout), limit]
          end
        end

        attr_reader :work

        def initialize(resolver:, runner: Runner.new, overrides: HOME, logs: File.join(TMP, "logs"),
                       work: File.join(TMP, "work"), keep: false, say: nil, reference: Harness::Reference, zr: Dev.path("exe/zr"))
          @resolver = resolver
          @runner = runner
          @overrides = overrides
          @logs = logs
          @work = work
          @keep = keep
          @say = say
          @reference = reference
          @zr = zr
        end

        # The Result for `request`.
        def call(request)
          log = []
          subject = nil
          override = request.name && Override.for(request.name, dir: @overrides)
          raise Failure.new("skip", override.skip, tier: :skipped) if override&.skip

          subject, deps = @resolver.resolve(request)
          say "found #{subject} (#{subject.source}), with #{deps.empty? ? "no gems" : deps.join(", ")}"
          log << "gem: #{subject} (#{subject.source}) #{subject.root}"
          deps.each { |dep| log << "needs: #{dep} (#{dep.source}) #{dep.root}" }
          override ||= Override.for(subject.name, dir: @overrides)
          raise Failure.new("skip", override.skip, tier: :skipped) if override&.skip
          refusal = Rules.refusal([subject, *deps])
          raise refusal if refusal

          features = override&.requires
          features = [entry(subject)] if features.nil? || features.empty?
          tier = in_work(subject) do |dir|
            check(dir, "probe.rb", Trial.probe(features), [subject, *deps], log)
            next :loads unless override&.smoke?

            begin
              check(dir, "smoke.rb", override.source, [subject, *deps], log)
              :verified
            rescue Failure => e
              raise Failure.new("smoke:#{e.kind}", e.message, tier: :loads)
            end
          end
          finish(request, subject, tier, nil, nil, log)
        rescue Failure => e
          finish(request, subject || e.subject, e.tier, e.kind, e.message, log)
        rescue Gem::Exception, SystemCallError, SocketError => e
          # A download, an unpack or a gemspec that fails.
          log << e.full_message(highlight: false)
          finish(request, subject, :fails, "resolve", "#{e.class}: #{e.message.lines.first&.chomp}", log)
        end

        # The feature that requires the gem: its name, its name with each
        # `-` as `/` (net-http as net/http), the .rb file at the top of its
        # require paths whose name is the gem's without `_` and `-`
        # (activerecord as active_record), or the only such file.
        def entry(subject)
          names = [subject.name, subject.name.tr("-", "/")].uniq
          roots = subject.roots.select { |root| File.directory?(root) }
          names.each { |name| return name if roots.any? { |root| File.file?(File.join(root, "#{name}.rb")) } }
          tops = roots.flat_map { |root| Dir.children(root).grep(/\.rb\z/) }.map { |file| file.delete_suffix(".rb") }.sort
          bare = ->(name) { name.delete("_-").downcase }
          alike = tops.find { |top| bare.(top) == bare.(subject.name) }
          return alike if alike
          return tops.first if tops.one?

          raise Failure.new("no-entry", "no #{names.map { |name| "#{name}.rb" }.join(" or ")} in #{subject.require_paths.join(", ")}; " \
                                        "name the require in gems/#{subject.name}.rb")
        end

        private

        def say(text) = @say&.call(text)

        # Builds and runs `name` with `text` in `dir`, and raises a
        # Failure when the binary does not give ruby's output.
        def check(dir, name, text, gems, log)
          File.write(File.join(dir, name), text)
          exe = name.delete_suffix(".rb")
          say "building #{name}"
          # A gem at the version that zr carries (its standard library and
          # its ports) comes from zr, and from the reference ruby's copy.
          gems = gems.reject { |gem| Resolver::Provided.versions[gem.name] == gem.version }
          flags = gems.flat_map { |gem| ["--gem", "#{gem.name}=#{gem.root}"] }
          built, limit = run(log, "zr build", [Dev.ruby, @zr, "build", *flags, name, "-o", exe],
                             dir: dir, seconds: BUILD_SECONDS, megabytes: Harness::Child::BUILD_MB, env: { "BUNDLE_GEMFILE" => nil })
          raise build_failure(built, limit) unless built.status&.zero?

          say "running #{name} under ruby and as a zr binary"
          # A gem with a C extension here is one that zr ports. An unpacked
          # copy has no compiled C, so ruby loads the reference's own copy.
          plain = gems.reject(&:cext?)
          env = @reference.env
          env = env.merge("GEM_PATH" => [env["GEM_PATH"], gem_home(dir, plain)].compact.join(File::PATH_SEPARATOR))
          ruby, = run(log, "ruby", [Dev.ruby, *plain.flat_map(&:roots).flat_map { |root| ["-I", root] }, name],
                      dir: dir, seconds: RUN_SECONDS, megabytes: Harness::Child::RUN_MB, env: env)
          unless ruby.status&.zero?
            raise Failure.new("ruby-error", "ruby: #{first_line(ruby.stderr) || ruby.status || "stopped"}", tier: :skipped)
          end

          zr, limit = run(log, "zr binary", ["./#{exe}"], dir: dir, seconds: RUN_SECONDS, megabytes: Harness::Child::RUN_MB)
          raise Failure.new("memory", "the binary used more than #{Harness::Child::RUN_MB} MB", tier: :compiles) if limit == :memory

          kind = Diff.kind(ruby, zr)
          return if kind == "same"

          log << "--- #{name}: #{kind}"
          Diff::PARTS.each do |part|
            log << "--- #{part} (ruby, then zr)\n#{Diff.unified(ruby[part].to_s, zr[part].to_s)}" unless ruby[part] == zr[part]
          end
          raise Failure.new(kind == "crash" ? "zr-crash" : kind, difference(ruby, zr), tier: :compiles)
        end

        # A gem directory in `dir` that holds `gems` as rubygems installs
        # them: a specification and a link to each gem's files. ruby reads
        # it from GEM_PATH, so a gem that activates another one (`gem
        # "parser", ">= 3.3"`, as rubocop-ast does) finds it.
        def gem_home(dir, gems)
          home = File.join(dir, "gem-home")
          FileUtils.rm_rf(home)
          FileUtils.mkdir_p([File.join(home, "gems"), File.join(home, "specifications")])
          gems.each do |gem|
            File.symlink(gem.root, File.join(home, "gems", gem.full_name))
            spec = gem.to_spec
            spec.require_paths = gem.require_paths
            File.write(File.join(home, "specifications", "#{gem.full_name}.gemspec"), spec.to_ruby)
          end
          home
        end

        def run(log, title, argv, **options)
          answer, limit = @runner.run(argv, **options)
          log << "$ #{argv.join(" ")}\n#{title}: #{limit || (answer.signal ? "signal #{answer.signal}" : "exit #{answer.status}")}"
          log << "stdout:\n#{answer.stdout}" unless answer.stdout.to_s.empty?
          log << "stderr:\n#{answer.stderr}" unless answer.stderr.to_s.empty?
          [answer, limit]
        end

        def build_failure(built, limit)
          return Failure.new("timeout", "the build ran longer than #{BUILD_SECONDS} s") if limit == :timeout
          return Failure.new("memory", "the build used more than #{Harness::Child::BUILD_MB} MB") if limit == :memory

          text = utf8(built.stderr)
          line = first_line(text).to_s.delete_prefix("zr: ")
          if (feature = text[/cannot load such file -- (\S+?)\.(?:\s|\z)/, 1])
            Failure.new("missing-require:#{feature}", line)
          elsif built.status == REFUSED
            form = text[/does not support (.+?) yet/, 1]
            form ||= "eval with an override" if text.include?("uses eval, so it carries")
            Failure.new(form ? "refused:#{form}" : "refused", line, tier: :refused)
          elsif built.signal || text.include?("internal error")
            Failure.new("zr-crash", line || "signal #{built.signal}")
          else
            Failure.new("build-error", line)
          end
        end

        # The first line where the two answers differ, in words.
        def difference(ruby, zr)
          return "the binary ran longer than #{RUN_SECONDS} s" if zr.timeout
          return "ruby: exit #{ruby.status}; zr: #{zr.signal ? "signal #{zr.signal}" : "exit #{zr.status}"}" if zr.signal || zr.status != ruby.status

          part = ruby.stderr == zr.stderr ? :stdout : :stderr
          want = utf8(ruby[part]).lines
          got = utf8(zr[part]).lines
          n = (0...[want.size, got.size].max).find { |i| want[i] != got[i] }
          "#{part} line #{n + 1}: ruby #{want[n].to_s.chomp.inspect}, zr #{got[n].to_s.chomp.inspect}"
        end

        def first_line(text) = utf8(text).lines.map(&:strip).find { |line| !line.empty? }

        def utf8(text) = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub

        # Runs the block in a new directory below `work`.
        def in_work(subject)
          dir = File.join(@work, "#{subject.full_name}-#{Time.now.strftime("%Y%m%d-%H%M%S")}-#{Process.pid}-#{Thread.current.object_id}")
          FileUtils.mkdir_p(dir)
          say "work directory: #{Dev.rel(dir)}" if @keep
          yield dir
        ensure
          FileUtils.rm_rf(dir) if dir && !@keep
        end

        def finish(request, subject, tier, kind, detail, log)
          name = subject&.name || request.label
          version = subject&.version || request.version.to_s
          path = File.join(@logs, "#{name}-#{version.empty? ? "unknown" : version}.txt")
          log << "result: #{tier}#{" #{kind}: #{detail}" if kind}"
          FileUtils.mkdir_p(@logs)
          File.write(path, "#{log.join("\n\n")}\n")
          Result.new(name: name, version: version, source: subject&.source || (request.path ? "path" : "rubygems"),
                     tier: tier, kind: kind, detail: detail, log: path)
        end
      end
    end
  end
end
