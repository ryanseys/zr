# frozen_string_literal: true

require "fileutils"
require "minitest"
require "tmpdir"
require_relative "harness/case"
require_relative "harness/child"
require_relative "harness/runner"
require_relative "../../lib/ze0/native/build"
require_relative "../../lib/ze0/zr"

module Ze0
  # What a spec example is: a Ruby program ze0 compiles, runs, and is
  # held to ruby 4.0.6's answer for.
  #
  # The compile happens in this process. A fresh ruby would reload the
  # whole compiler for every example, and that fixed cost is the whole
  # cost of a small program; loading it once and compiling many is what
  # makes a suite of thousands finish. Ruby does not give heap pages
  # back, so a process is bounded by `Supervisor`, which starts one per
  # file and recycles it.
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

    # The census every process writes and the run adds up: the buckets
    # `ze0 test` counted, and the sentence each refusal names.
    class Census
      def initialize = @rows = []

      def <<(row) = @rows << row

      def save(path)
        return if @rows.empty?

        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "a") { |f| @rows.each { |bucket, why| f.puts("#{bucket}\t#{why}") } }
      end

      def self.current = @current ||= new

      # Where this process leaves its rows. One file a process: two
      # writers never share a line.
      def self.path(root) = File.join(root, "tmp", "census", "#{Process.pid}.tsv")
    end

    module_function

    # The name the recordings use for the machine these examples run on.
    def platform = Harness::Runner::PLATFORMS.fetch(Target.default.os)

    # Whether this machine has what a `#@ needs:` name asked for.
    def need?(name) = Harness::Needs.met?(name, platform)

    # Compile `source` with ze0 and run what it built. `path` is the
    # name the program answers to -- its backtraces carry it -- and is
    # relative to the directory the program runs in. `files` writes the
    # program's own fixtures beside it.
    def build_and_run(source, path:, argv: [], env: {}, stdin: nil, files: {}, target: Target.default, seconds: nil)
      Dir.mktmpdir("ze0-spec-") do |work|
        run = File.join(work, "run")
        rb = File.join(run, path)
        FileUtils.mkdir_p(File.dirname(rb))
        File.write(rb, source)
        files.each do |name, bytes|
          beside = File.expand_path(name, File.dirname(rb))
          FileUtils.mkdir_p(File.dirname(beside))
          File.binwrite(beside, bytes)
        end

        program = lower(source, rb, target)
        return program if program.is_a?(Symbol) || program.is_a?(Array)

        bin = File.join(work, "p")
        if (why = Native::Build.program(program, bin, work: work))
          return [:backend, why]
        end

        out, = Harness::Child.run([bin, *argv], cwd: run, stdin: stdin, env: env,
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

    # What a spec example says: `ze0 "puts 1"` answers a Result, or
    # skips when ze0 refused the program or could not build it.
    module DSL
      ROOT = File.expand_path("../..", __dir__)

      def ze0(source, path: nil, argv: [], env: {}, stdin: nil, files: {}, seconds: nil)
        out = Spec.build_and_run(source, path: path || default_path, argv: argv, env: env,
                                         stdin: stdin, files: files, seconds: seconds)
        return out if out.is_a?(Spec::Result)

        bucket, why = out
        raise Minitest::Assertion, "#{bucket}: #{why}" if bucket == :timeout

        Spec::Census.current << [bucket, shape(why)]
        skip("#{bucket}: #{why}")
      end

      # The name the program answers to when an example does not name
      # one: its own, so a backtrace reads as the example reads.
      def default_path = "#{name.gsub(/[^\w]+/, "_").delete_prefix("test_")}.rb"

      # The sentence a refusal names, with the file and line taken off,
      # so the census counts gaps and not places.
      def shape(why)
        (why[/(?:line \d+|run time): (.*)\z/, 1] || why).delete_suffix(" is not in ze0's subset")
      end
    end
  end
end

Minitest.after_run do
  Ze0::Spec::Census.current.save(Ze0::Spec::Census.path(Ze0::Spec::DSL::ROOT))
end
