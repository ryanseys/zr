# frozen_string_literal: true

require "fileutils"
require "minitest"
require "tmpdir"
require_relative "baseline"
require_relative "harness/answer"
require_relative "fixtures"
require_relative "reader"
require_relative "harness/child"
require_relative "harness/runner"
require_relative "slow"
require_relative "binaries"
require_relative "../../lib/zr/native/build"
require_relative "../../lib/zr/runtime"

module Zr
  # Runs spec examples. An example is a Ruby program that zr compiles and
  # runs, and the test checks its output against ruby 4.0.7.
  #
  # The worker that gets the example compiles it in process. A new ruby
  # process for each example would load the whole compiler each time,
  # and for a small program that load is almost all of the cost. Ruby
  # does not release heap pages, so `ForkPool` replaces a worker that
  # grows too much with a new fork of the parent.
  module Spec
    # The output of a compiled program. When a POSIX signal stopped the
    # process, `signal` is set and `status` is nil, because such a
    # process has no exit status.
    Result = Struct.new(:stdout, :stderr, :status, :signal) do
      def success? = status.zero? && signal.nil?
    end

    # Returns a stream as UTF-8 text when it is valid UTF-8, and as bytes
    # when it is not. Thus an example can compare with `"\u00e9\n"`, not
    # with its bytes. A program can write any bytes, so invalid UTF-8
    # stays binary.
    def self.text(bytes)
      out = bytes.dup.force_encoding(Encoding::UTF_8)
      out.valid_encoding? ? out : bytes
    end

    # Long enough for the slowest program, and short enough that a
    # miscompiled infinite loop does not stop the run (the limit of every
    # test, `Checks::LIMIT`). With GC stress, a collection at each
    # allocation marks all live objects, so a stress run gets four times
    # the limit.
    LIMIT = Checks::LIMIT

    def self.limit = ENV["ZR_GC_STRESS"] == "1" ? LIMIT * 4 : LIMIT

    # A refusal is not a defect: zr does not support the form. The
    # example skips with the message of the refusal.
    REFUSALS = [Zr::Refused].freeze

    # An unrescued stop at run time: the ruby report of a
    # NotImplementedError or LoadError, or a stop from the kernel.
    STOP = /^(?:zr: |.*?:in '[^']*': )?(.* is not implemented yet)(?: \((?:NotImplementedError|LoadError)\))?$/

    # A Minitest plugin that counts refusals by kind and message, and
    # prints the totals at the end of a run.
    #
    # An example that zr refuses skips. The refused forms show what zr
    # must support next. Each skip writes its kind and message to the
    # metadata of the result. Minitest sends the metadata back from the
    # worker, and this reporter counts it.
    module Census
      KEY = :zr_refusal

      def self.minitest_plugin_init(options)
        Minitest.reporter << Reporter.new(options[:io])
      end

      class Reporter < Minitest::AbstractReporter
        def initialize(io)
          super()
          @io = io
          @rows = Hash.new(0)
        end

        def record(result)
          row = result.metadata[KEY] if result.metadata?
          @rows[row] += 1 if row
        end

        def report
          return if @rows.empty?

          @rows.group_by { |(bucket, _), _| bucket }.sort.each do |bucket, rows|
            @io.puts format("\n%d %s, by shape:", rows.sum(&:last), bucket)
            rows.sort_by { |row, n| [-n, row.last] }.each { |(_, why), n| @io.puts format("%6d  %s", n, why) }
          end
        end
      end
    end

    module_function

    # The target for all examples. `ZR_TARGET` selects a different
    # target, as the cross-target CI jobs do. A triple that this host
    # cannot run fails here one time, not at each example.
    def target
      @target ||= Harness::Runner.named(ENV["ZR_TARGET"])
    end

    # The examples that this target can fail, and why (`Test::Baseline`).
    def allowed = @allowed ||= Test::Baseline.for(target)

    # The baseline key of `example`: its file below `test/` and its
    # description.
    def key(example)
      file = example.class.instance_method(example.name).source_location.first
      "#{file.delete_prefix("#{DSL::ROOT}/test/")}: #{example.name.sub(/\Atest_\d+_/, "")}"
    end

    # The runner that starts the output of this target: a binary on its
    # host, or a WASI module under wasmtime.
    def runner = @runner ||= Harness::Runner.new(DSL::ROOT, target)

    # The platform name that the recordings use for this machine.
    def platform = runner.platform

    # Returns true if this machine has the item that a `needs:` name
    # requires.
    def need?(name) = Harness::Needs.met?(name, platform)

    # Compiles `source` with zr and runs the result. `path` is the path of
    # the program, relative to the directory it runs in. Backtraces show
    # it. `files` writes the fixtures of the program next to it.
    #
    # `phases` is a hash; each build part adds its seconds to it, for the
    # `SLOW` report (`Zr::Test::Slow`).
    def build_and_run(source, path:, argv: [], env: {}, stdin: nil, files: {}, seconds: nil, phases: nil)
      Dir.mktmpdir("zr-spec-") do |work|
        # Use the resolved path, not the path from `mktmpdir`. On macOS,
        # `/var` is a link to `/private/var`, and a program prints the
        # resolved path. The normalization that makes an absolute path
        # relative must see the same bytes, or `/private` stays in front.
        work = File.realpath(work)
        run = File.join(work, "run")
        rb = File.join(run, path)
        FileUtils.mkdir_p(File.dirname(rb))
        File.write(rb, source)
        files.each do |name, bytes|
          beside = File.expand_path(name, File.dirname(rb))
          # A fixture with the same path as the program overwrites it,
          # because `files:` is written after the source. Then the example
          # runs the fixture and gives wrong output with no error. Give
          # the program a different name with `path:`.
          raise ArgumentError, "the fixture #{name.inspect} lands on the program itself" if beside == rb

          FileUtils.mkdir_p(File.dirname(beside))
          # `{ symlink: "lib" }` makes a symbolic link, not a file. A
          # program that checks if two paths are the same file needs one.
          bytes.is_a?(Hash) ? File.symlink(bytes.fetch(:symlink), beside) : File.binwrite(beside, bytes)
        end

        # Compile from the directory where the program runs, with its
        # relative path. The backtraces of the binary show the path that
        # the compiler gets. An absolute path would show the temporary
        # directory. The chdir is safe because each worker is a separate
        # process and runs one example at a time.
        bin = binary_path
        kept = Binaries.path(target, source, path, files) if Binaries.wanted?(target)
        unless Binaries.take(kept, bin)
          program = Test::Slow.clock(phases, :lower) { Dir.chdir(run) { lower(source, path, target) } }
          return program if program.is_a?(Symbol) || program.is_a?(Array)

          if (why = Test::Slow.clock(phases, :link) { write(program, bin, work, target) })
            return [:backend, why]
          end
          Binaries.keep(kept, bin, program, work)
        end

        # A binary starts on its host. A WASI module starts under wasmtime,
        # with its run directory preopened.
        command, child_env = runner.run(bin, argv, env)
        out, = Test::Slow.clock(phases, :run) do
          Harness::Child.run(command, cwd: run, stdin: stdin, env: child_env,
                                      seconds: seconds || Spec.limit,
                                      megabytes: Harness::Child::RUN_MB)
        end
        verdict(Harness::Normalize.answer(out, rb, run))
      end
    end

    # Returns the path where this worker writes each binary. Each binary
    # overwrites the previous one. Then the text pages of the runtime stay
    # in memory. A new file reads them from disk at each exec
    # (`Obj::MachO::Skeleton`): 40 ms a run, and eight workers that read
    # at the same time wait for each other. The tier makes the directory
    # before the workers start (`binaries_dir`) and removes it at the end.
    # Each worker writes in a subdirectory named by its pid.
    def binary_path
      dir = File.join(binaries_dir, Process.pid.to_s)
      FileUtils.mkdir_p(dir)
      File.join(dir, "p")
    end

    def binaries_dir
      @binaries_dir ||= Dir.mktmpdir("zr-bins-").tap { |dir| at_exit { FileUtils.rm_rf(dir) } }
    end

    # Returns the program, or `[kind, why]` when zr does not build it.
    def lower(source, rb, target)
      compile(source, rb, target)
    rescue *REFUSALS => e
      [:refused, e.message]
    rescue Backend::Refused => e
      [:backend, e.message]
    rescue SyntaxError => e
      # For a program that does not parse, ruby prints a report and exits
      # 1. The binary does the same, with the ruby report. `Zr::CLI.lower`
      # does the same, and the two must stay the same.
      report = syntax_report(rb)
      return [:refused, "a required file does not parse: #{e.message.lines.first.chomp}"] unless report

      compile("$stderr.write(#{report.inspect})\nexit 1\n", rb, target)
    end

    # A native target builds its runtime object before it lowers the
    # program. A WASI module takes the runtime from the cached prelude.
    def compile(source, rb, target)
      target.link ? Native::Build.lower(source, rb, target: target) : Zr.program(source, rb, target: target)
    end

    # Writes `program` to `bin`. Returns nil, or the message of the step
    # that refused.
    def write(program, bin, work, target)
      target.link ? Native::Build.program(program, bin, work: work) : Native::Build.wasm_program(program, bin)
    end

    # The program that a bare ruby runs to write the report. It prints the
    # file path as given, because the binary contains that path. The
    # parse warnings come first, as in ruby.
    REPORT = <<~'RUBY'
      $stderr = $stdout
      begin
        RubyVM::InstructionSequence.compile_file(ARGV[0])
      rescue SyntaxError => e
        print ARGV[0], ": ", e.detailed_message(highlight: false), "\n"
      end
    RUBY

    # Returns the ruby report for a file that does not parse. Returns nil
    # when ruby parses it, and the error came from a required file.
    #
    # A bare ruby writes the report, not this process. The report uses
    # syntax_suggest. Under `bundle exec`, a gem that the Gemfile does
    # not list is hidden, so this process gets the older copy in lib/ruby
    # (2.0.3, not 3.0.0), which writes different text. A bare ruby made
    # the recordings, so a bare ruby writes this report too.
    # `Zr::CLI.lower` uses the ruby that it runs under, which for a user
    # is also a bare ruby.
    def syntax_report(rb)
      out, = Harness::Child.run([RbConfig.ruby, "-e", REPORT, rb], cwd: Dir.pwd, seconds: Spec.limit,
                                                                   megabytes: Harness::Child::RUN_MB,
                                                                   env: Harness::Child::BARE_RUBY)
      out.stdout.empty? ? nil : Spec.text(out.stdout)
    end

    # Returns the Result of the binary, or `[kind, why]` when the output
    # does not count.
    def verdict(answer)
      return [:timeout, "ran past #{Spec.limit}s"] if answer.code == :timeout
      return [:backend, "held more than #{Harness::Child::RUN_MB} MB"] if answer.code == :memory
      if (stop = answer.stderr[STOP, 1])
        return [:refused, "run time: #{stop}"]
      end

      Result.new(text(answer.stdout), text(answer.stderr), answer.code, answer.signal)
    end

    # `_(result).must_answer "AB\n"` checks the whole output. stderr must
    # be empty and the status must be zero, unless the example gives
    # other values. A check of stdout alone would pass a program that
    # also wrote a backtrace.
    module Expectation
      # `linux:` and `wasi:` give the stdout for that platform. A
      # platform that the call does not name expects the macOS stdout.
      def must_answer(stdout, stderr: "", status: 0, signal: nil, linux: nil, wasi: nil)
        result = target
        stdout = { "linux" => linux, "wasi" => wasi }.fetch(Spec.platform, nil) || stdout
        ctx.assert_equal stdout, result.stdout, "stdout"
        ctx.assert_equal stderr, result.stderr, "stderr"
        signal.nil? ? ctx.assert_nil(result.signal, "signal") : ctx.assert_equal(signal, result.signal, "signal")
        status.nil? ? ctx.assert_nil(result.status, "exit status") : ctx.assert_equal(status, result.status, "exit status")
        result
      end
    end

    # Applies the target's baseline to each example. A listed example
    # that fails is a skip with the reason. A listed example that passes
    # fails, so the baseline stays current.
    module Baselined
      def after_teardown
        super
        why = Spec.allowed[Spec.key(self)] or return

        triple = Spec.target.triple
        if failures.empty?
          failures << Minitest::Assertion.new("this now passes: take it off test/baselines/#{triple}.txt")
        elsif failures.none?(Minitest::Skip)
          failures.replace([Minitest::Skip.new("the #{triple} baseline allows this: #{why}")])
        end
      end
    end

    # `it "...", needs: "libssl"` and `it "...", only: "macos"` skip an
    # example that this machine cannot run. The guard runs before the
    # example, so the example's method keeps the source location of its
    # block: the default path and the baseline key read it.
    module Guards
      # The class side, prepended to `Minitest::Spec.singleton_class`.
      module It
        def it(desc = "anonymous", needs: nil, only: nil, &)
          name = super(desc, &)
          guards[name] = [Array(needs), Array(only)] if needs || only
          name
        end

        def guards = @guards ||= {}

        def guard_of(name)
          guards.fetch(name) { superclass.respond_to?(:guard_of) ? superclass.guard_of(name) : nil }
        end
      end

      # Returns the reason to skip, or nil. The reader gives the same
      # reasons (`Reader::Sandbox#it`).
      def self.unmet(needs, only, platform)
        return "runs only on #{only.join(", ")}" unless only.empty? || only.include?(platform)

        need = needs.find { |name| !Harness::Needs.met?(name, platform) }
        "needs #{need}" if need
      end

      def before_setup
        super
        needs, only = self.class.guard_of(name)
        why = needs && Guards.unmet(needs, only, Spec.platform)
        skip why if why
      end
    end

    # The spec DSL. `zr "puts 1"` returns a Result, or skips when zr
    # refuses the program or cannot build it.
    module DSL
      include Fixtures

      ROOT = File.expand_path("../..", __dir__)

      # `ruby:` gives flags for ruby only; zr does not use them. They are
      # kept so that `zr-dev oracle` runs ruby with the same program and
      # input as zr.
      def zr(source, path: nil, argv: [], env: {}, stdin: nil, files: {}, seconds: nil, ruby: [])
        phases = (metadata[Test::Slow::KEY] ||= {}) if Test::Slow.asked?
        out = Spec.build_and_run(source, path: path || default_path, argv: argv, env: env,
                                         stdin: stdin, files: files, seconds: seconds, phases: phases)
        return out if out.is_a?(Spec::Result)

        bucket, why = out
        raise Minitest::Assertion, "#{bucket}: #{why}" if bucket == :timeout

        metadata[Spec::Census::KEY] = [bucket, shape(why)]
        skip("#{bucket}: #{why}")
      end

      # The path of the program when an example gives none: the path of
      # the spec file, so a backtrace shows where the example is. `it`
      # defines a method, and the method knows its source file. The path
      # does not change when the example description changes.
      def default_path = Reader.path_for(method(name).source_location.first)

      # Returns the refusal message without the file and line, so that
      # `Census` counts unsupported forms, not locations.
      def shape(why)
        (why[/(?:line \d+|run time): (.*)\z/, 1] || why).delete_suffix(" is not in zr's subset")
      end
    end
  end
end

Minitest.register_plugin(Zr::Spec::Census)
