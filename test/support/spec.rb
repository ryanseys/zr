# frozen_string_literal: true

require "fileutils"
require "minitest"
require "tmpdir"
require_relative "harness/answer"
require_relative "fixtures"
require_relative "reader"
require_relative "harness/child"
require_relative "harness/runner"
require_relative "../../lib/ze0/native/build"
require_relative "../../lib/ze0/zr"

module Ze0
  # What a spec example is: a Ruby program ze0 compiles, runs, and is
  # held to ruby 4.0.6's answer for.
  #
  # The compile happens in the worker that was handed the example. A
  # fresh ruby would reload the whole compiler for every one, and that
  # fixed cost is the whole cost of a small program; loading it once and
  # compiling many is what makes a suite of thousands finish. Ruby does
  # not give heap pages back, so `ForkPool` closes a worker that has
  # grown and forks another from the parent, which has not.
  module Spec
    # What a compiled program said. `signal` is set and `status` nil
    # when a signal ended it, as a process a signal ends has no status.
    Result = Struct.new(:stdout, :stderr, :status, :signal) do
      def success? = status.zero? && signal.nil?
    end

    # A stream reads as text where it is text, and as bytes where it is
    # not, so an example compares against `"\u00e9\n"` and not against
    # the four bytes that spells. A program may write anything, so the
    # bytes are what survive when they are not UTF-8.
    def self.text(bytes)
      out = bytes.dup.force_encoding(Encoding::UTF_8)
      out.valid_encoding? ? out : bytes
    end

    # Long enough for the slowest program, short enough that a
    # miscompile that loops does not stall the run. A collection at
    # every allocation marks the live set each time, so a stress run
    # gets four times as long.
    LIMIT = Integer(ENV.fetch("ZE0_LIMIT", 60))

    def self.limit = ENV["ZR_GC_STRESS"] == "1" ? LIMIT * 4 : LIMIT

    # The forms ze0 names as outside its subset. A refusal is not a
    # defect: it is the roadmap, and it skips the example by name.
    REFUSALS = [Machine::Refused, Hir::Refused, Zr::Lower::Refused].freeze

    # A stop at run time the program did not rescue: ruby's report of
    # the NotImplementedError or LoadError it raised, or a kernel stop.
    STOP = /^(?:ze0: |.*?:in '[^']*': )?(.* is not implemented yet)(?: \((?:NotImplementedError|LoadError)\))?$/

    # The buckets `ze0 test` counted, added up at the end of a run.
    #
    # An example ze0 refused makes no claim about ruby and skips, but
    # which forms it refused is the roadmap. Each one leaves its bucket
    # and the sentence it named in the result's metadata, which minitest
    # carries back from the worker that ran it, and this counts them.
    # It is a minitest plugin, which is how a run gains a report.
    module Census
      KEY = :ze0_refusal

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

    # The target every example is built for. `ZE0_TARGET` names another
    # one, as the cross-target rows of CI do; a triple this host cannot
    # run is refused where it is named rather than at every example.
    def target
      @target ||= Harness::Runner.named(ENV["ZE0_TARGET"])
    end

    # The runner that knows how to start what this target builds: a
    # binary on its own host, a module under wasmtime.
    def runner = @runner ||= Harness::Runner.new(DSL::ROOT, target)

    # The name the recordings use for the machine these examples run on.
    def platform = runner.platform

    # Whether this machine has what a `#@ needs:` name asked for.
    def need?(name) = Harness::Needs.met?(name, platform)

    # Compile `source` with ze0 and run what it built. `path` is the
    # name the program answers to -- its backtraces carry it -- and is
    # relative to the directory the program runs in. `files` writes the
    # program's own fixtures beside it.
    def build_and_run(source, path:, argv: [], env: {}, stdin: nil, files: {}, seconds: nil)
      Dir.mktmpdir("ze0-spec-") do |work|
        # The resolved path, not the one `mktmpdir` hands back: on macOS
        # `/var` is a link to `/private/var`, and a program that prints a
        # path of its own prints the resolved one. The scrub that turns
        # an absolute path back into a relative one has to be looking at
        # the same bytes, or it leaves `/private` glued to the front.
        work = File.realpath(work)
        run = File.join(work, "run")
        rb = File.join(run, path)
        FileUtils.mkdir_p(File.dirname(rb))
        File.write(rb, source)
        files.each do |name, bytes|
          beside = File.expand_path(name, File.dirname(rb))
          FileUtils.mkdir_p(File.dirname(beside))
          # `{ symlink: "lib" }` is a link, not a file: a program that
          # asks whether two paths reach one file needs one.
          bytes.is_a?(Hash) ? File.symlink(bytes.fetch(:symlink), beside) : File.binwrite(beside, bytes)
        end

        # From the directory the program runs in, under the name it
        # answers to: `ze0 build` is given a relative path, and what it
        # is given is what the binary's backtraces carry. Compiling with
        # an absolute path would name the temporary directory instead.
        # The chdir is safe because a worker is a process of its own and
        # runs the examples it is handed one at a time.
        program = Dir.chdir(run) { lower(source, path, target) }
        return program if program.is_a?(Symbol) || program.is_a?(Array)

        bin = File.join(work, "p")
        if (why = Native::Build.program(program, bin, work: work))
          return [:backend, why]
        end

        # A binary starts on its own host; a wasm module starts under
        # wasmtime, with the directory it runs in preopened.
        command, child_env = runner.run(bin, argv, env)
        out, = Harness::Child.run(command, cwd: run, stdin: stdin, env: child_env,
                                           seconds: seconds || Spec.limit,
                                           megabytes: Harness::Child::RUN_MB)
        verdict(Harness::Normalize.answer(out, rb, run))
      end
    end

    # The program, or `[bucket, why]` when ze0 would not build it.
    def lower(source, rb, target)
      Native::Build.lower(source, rb, target: target)
    rescue *REFUSALS => e
      [:refused, e.message]
    rescue Backend::Refused => e
      [:backend, e.message]
    rescue SyntaxError => e
      # ruby reports a program that does not parse and exits 1, and so
      # does the binary, with ruby's own report. `Ze0::CLI.lower` does
      # this the same way, and the two must stay the same way.
      report = syntax_report(rb)
      return [:refused, "a required file does not parse: #{e.message.lines.first.chomp}"] unless report

      Native::Build.lower("$stderr.write(#{report.inspect})\nexit 1\n", rb, target: target)
    end

    # ruby's own report for a file that does not parse, or nil when ruby
    # parses it and the stop came from something it required.
    def syntax_report(rb)
      begin
        require "rubygems"
        require "syntax_suggest/core_ext"
      rescue LoadError
        nil
      end
      RubyVM::InstructionSequence.compile_file(rb)
      nil
    rescue SyntaxError => own
      "#{rb}: #{own.detailed_message(highlight: false)}\n"
    end

    # What the binary said, or why it does not count as an answer.
    def verdict(answer)
      return [:timeout, "ran past #{Spec.limit}s"] if answer.code == :timeout
      return [:backend, "held more than #{Harness::Child::RUN_MB} MB"] if answer.code == :memory
      if (stop = answer.stderr[STOP, 1])
        return [:refused, "run time: #{stop}"]
      end

      Result.new(text(answer.stdout), text(answer.stderr), answer.code, answer.signal)
    end

    # `_(result).must_answer "AB\n"` -- the whole answer, not a part of
    # it. stderr must be empty and the status zero unless the example
    # says otherwise, which is what the recordings mean: a trailer with
    # no `#@ stderr` says stderr **is** empty, and one with no
    # `#@ exit` says the status **is** zero. An example that asserted
    # stdout alone would pass a program that also wrote a backtrace.
    module Expectation
      # `linux:` and `wasi:` give that platform's stdout in place of
      # this one, which is what a `#@ linux stdout` section in a
      # recording says. A platform a call does not name answers what
      # macOS answers, as a recording without its section does.
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

    # What a spec example says: `ze0 "puts 1"` answers a Result, or
    # skips when ze0 refused the program or could not build it.
    module DSL
      include Fixtures

      ROOT = File.expand_path("../..", __dir__)

      # `ruby:` names flags for the oracle alone, which ze0 has no use
      # for: it is carried so that `rake oracle` can ask ruby the same
      # question this example asked ze0.
      def ze0(source, path: nil, argv: [], env: {}, stdin: nil, files: {}, seconds: nil, ruby: [])
        out = Spec.build_and_run(source, path: path || default_path, argv: argv, env: env,
                                         stdin: stdin, files: files, seconds: seconds)
        return out if out.is_a?(Spec::Result)

        bucket, why = out
        raise Minitest::Assertion, "#{bucket}: #{why}" if bucket == :timeout

        metadata[Spec::Census::KEY] = [bucket, shape(why)]
        skip("#{bucket}: #{why}")
      end

      # The name the program answers to when an example does not name
      # one: its own, so a backtrace reads as the example reads.
      # Minitest numbers the method it defines for an `it`; the number
      # is not part of the sentence and is not part of the name.
      def default_path = Reader.path_for(name.sub(/\Atest_\d+_/, ""))

      # The sentence a refusal names, with the file and line taken off,
      # so the census counts gaps and not places.
      def shape(why)
        (why[/(?:line \d+|run time): (.*)\z/, 1] || why).delete_suffix(" is not in ze0's subset")
      end
    end
  end
end

Minitest.register_plugin(Ze0::Spec::Census)
