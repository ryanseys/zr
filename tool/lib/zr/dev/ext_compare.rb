# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require_relative "../dev"
require_relative "../../../../test/support/harness/child"
require_relative "../../../../test/support/harness/normalize"

module Zr
  module Dev
    # zr's port of a gem's C against the gem's real C extension
    # (`zr-dev ext compare`): the same programs (test/programs/stdlib/<gem>/)
    # built both ways, each checked against ruby's output, timed, and
    # measured. The table that it prints is what docs/reference/
    # ports-vs-native.md records.
    module ExtCompare
      # How a build takes the gem: with zr's port, or with the C extension
      # that this ruby installed (`--native-ext`).
      WAYS = %i[port native].freeze

      # One program built one way: whether it gave ruby's output, its
      # fastest wall time of RUNS runs, and the size of its binary. A
      # build that failed has neither.
      Run = Data.define(:program, :way, :ok, :seconds, :bytes)

      RUNS = 3
      # The most seconds that one build, or one run, takes.
      LIMIT = 600

      module_function

      # Each program of `gem` built each way into `work`, one at a time.
      # A program that pins its own gem version (a `.gems` sidecar) is
      # left out: the comparison is of one version.
      def compare(gem, work)
        programs = Dir[File.join(Paths::ROOT, "test/programs/stdlib", gem, "*.rb")].sort
        programs.reject! { |program| File.exist?("#{program}.gems") }
        programs.flat_map { |program| WAYS.map { |way| run(gem, program, way, work) } }
      end

      # Builds `program` the `way` given, then runs it RUNS times.
      def run(gem, program, way, work)
        bin = File.join(work, way.to_s, File.basename(program, ".rb"))
        FileUtils.mkdir_p(File.dirname(bin))
        flags = way == :native ? native_flags(gem) : []
        built = capture(File.join(Paths::ROOT, "bin", "zr"), "build", *flags, program, "-o", bin)
        return Run.new(program, way, false, nil, nil) unless built.code == 0

        expected = File.binread("#{program}.expected")
        dir = File.dirname(program)
        times = Array.new(RUNS) do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          answer = capture(bin, chdir: dir)
          # The program tests' own check: addresses and paths masked.
          same = Harness::Normalize.bytes(answer.stdout, program, dir) == expected
          [Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, same && answer.code == 0]
        end
        Run.new(program, way, times.all?(&:last), times.map(&:first).min, File.size(bin))
      end

      # The flags of a build with the gem's own C: `--native-ext` links the
      # C of the newest installed version, and `--gem` takes that version's
      # Ruby half with it, as docs/how-to/use-a-c-extension.md says. Ruby's
      # copy of a default gem can be older than the C (strscan 3.1.8's
      # strscan.rb requires its Ruby methods; 3.1.6's C did).
      def native_flags(gem)
        specs = Dir[File.join(Gem.default_dir, "specifications", "#{gem}-*.gemspec")].filter_map { Gem::Specification.load(_1) }
        version = specs.select { _1.name == gem }.max_by(&:version)&.version
        ["--native-ext", gem, *(["--gem", "#{gem}=#{version}"] if version)]
      end

      # The answer of `command`, killed after LIMIT seconds (its code is
      # then :timeout).
      def capture(*command, chdir: Dir.pwd) = Harness::Child.run(command, cwd: chdir, seconds: LIMIT, megabytes: nil).first

      # The table's row for `gem`: the programs, how many give ruby's output
      # each way, the total of the fastest times, and the mean binary size.
      def row(gem, runs)
        by_way = runs.group_by(&:way)
        cells = WAYS.map do |way|
          done = by_way.fetch(way, []).select(&:seconds)
          [done.count(&:ok), done.sum(&:seconds), done.empty? ? 0 : done.sum(&:bytes) / done.size]
        end
        (port_ok, port_s, port_b), (native_ok, native_s, native_b) = cells
        format("| %s | %d | %d | %d | %.2f s | %.2f s | %.1f MB | %.1f MB |", gem, runs.size / WAYS.size, port_ok, native_ok,
               port_s, native_s, port_b / 1e6, native_b / 1e6)
      end

      HEADER = <<~MD
        | Gem | Programs | Pass (port) | Pass (native) | Time (port) | Time (native) | Size (port) | Size (native) |
        |---|---|---|---|---|---|---|---|
      MD
    end
  end
end
