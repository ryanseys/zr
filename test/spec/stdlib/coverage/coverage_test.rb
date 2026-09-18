# frozen_string_literal: true

require "spec_helper"

describe "Coverage programs" do
  it "the lifecycle, its error shapes and the measured line array all match the C extension" do
    result = ze0(<<~'RUBY', path: "coverage.rb", files: beside("coverage/target.rb"))
      # Line coverage over the AOT instrumentation: the lifecycle and its error
      # shapes, then the real measurement of coverage/target.rb -- required AFTER
      # Coverage.start, so it is reported (this file, loaded before, is not --
      # CRuby's own inclusion rule). The line array is compared byte-for-byte
      # against the C extension: def lines, class lines, per-call body counts, an
      # unentered branch's 0, and the nil non-executable lines.
      require "coverage"
      p Coverage.supported?(:lines)
      p Coverage.state
      p Coverage.running?
      begin
        Coverage.result
      rescue RuntimeError => e
        p [e.class, e.message]
      end
      begin
        Coverage.supported?("lines")
      rescue TypeError => e
        p [e.class, e.message]
      end
      Coverage.start
      p Coverage.state
      p Coverage.running?
      begin
        Coverage.start
      rescue RuntimeError => e
        p [e.class, e.message]
      end
      require_relative "coverage/target"
      c = CovCounter.new(1)
      p c.bump
      p c.bump
      p c.big?
      p cov_add(20, 22)
      peek = Coverage.peek_result
      p peek.size
      res = Coverage.result
      p Coverage.state
      p Coverage.running?
      p res.size
      res.each do |path, lines|
        puts File.basename(path)
        p lines
      end
      p peek == res
      begin
        Coverage.result
      rescue RuntimeError => e
        p [e.class, e.message]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      :idle
      false
      [RuntimeError, "coverage measurement is not enabled"]
      [TypeError, "wrong argument type String (expected Symbol)"]
      :running
      true
      [RuntimeError, "coverage measurement is already setup"]
      2
      3
      false
      42
      1
      :idle
      false
      1
      target.rb
      [1, 4, nil, nil, 1, 0, nil, nil, 1, 1, 1, nil, nil, 1, 2, 2, nil, nil, 1, 1, 0, nil, 1, nil, nil, nil, nil, 1, nil, 1, 3, nil]
      true
      [RuntimeError, "coverage measurement is not enabled"]
    OUT
  end

  it "lines and oneshot_lines answer as hashes of targets, and each state refuses what it must" do
    result = ze0(<<~'RUBY', files: beside("coverage_modes/lib_a.rb", "coverage_modes/lib_b.rb", "coverage/target.rb"))
      # Coverage's modes: lines and oneshot_lines as hashes of targets, the
      # counts a suspend leaves out, a result that keeps measuring, and the
      # errors each state refuses with.
      require "coverage"

      Coverage.setup(lines: true)
      p Coverage.state
      require_relative "coverage_modes/lib_a"
      twice(1)
      Coverage.resume
      twice(2)
      pick(true)
      Coverage.suspend
      pick(false)
      p((Coverage.suspend rescue $!))
      Coverage.resume
      p((Coverage.resume rescue $!))
      p((Coverage.setup rescue $!))
      kept = Coverage.result(stop: false, clear: true)
      kept.each { |path, value| p [File.basename(path), value] }
      p Coverage.state
      twice(3)
      p Coverage.peek_result.transform_keys { |path| File.basename(path) }
      Coverage.result
      p Coverage.state

      Coverage.start(oneshot_lines: true)
      require_relative "coverage_modes/lib_b"
      tally = Tally.new
      3.times { tally.add }
      Coverage.result.each { |path, value| p [File.basename(path), value] }

      p((Coverage.start(lines: true, oneshot_lines: true) rescue $!))
      p Coverage.state
      p((Coverage.resume rescue $!))
      p [Coverage.supported?(:branches), Coverage.supported?(:all)]

    RUBY

    _(result).must_answer <<~'OUT'
      :suspended
      #<RuntimeError: coverage measurement is not running>
      #<RuntimeError: coverage measurement is already running>
      #<RuntimeError: coverage measurement is already setup>
      ["lib_a.rb", {lines: [0, 1, nil, nil, 0, 1, 1, nil, 0, nil, nil]}]
      :running
      {"lib_a.rb" => {lines: [0, 1, nil, nil, 0, 0, 0, nil, 0, nil, nil]}}
      :idle
      ["lib_b.rb", {oneshot_lines: [1, 2, 4, 5]}]
      #<RuntimeError: cannot enable lines and oneshot_lines simultaneously>
      :idle
      #<RuntimeError: coverage measurement is not set up yet>
      [true, false]
    OUT
  end
end
