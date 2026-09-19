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

  it "names every branch the way the C extension names it" do
    result = ze0(<<~'RUBY', files: beside("coverage/branching.rb"))
      # Branch coverage over the AOT instrumentation, against the C
      # extension row for row: the key is [kind, id, start line, start
      # column, end line, end column] with 0-based columns, and the ids
      # run from 0 a file, a root then its sides.
      #
      # branching.rb carries every kind CRuby records one for and the
      # ones it records none for. `||` and `&&` are not branches, an
      # `elsif` is a nested :if at the outer :else's location, `unless`
      # lists :else before :then, a `case/in` gets an :else at the case's
      # own location with nothing in the source to put there, and `&.`
      # puts both sides where the call stands. A predicate ruby's
      # compiler decides -- the last `if` here -- keeps its branch, and
      # one it can fold away would keep none.
      require "coverage"
      Coverage.start(branches: true)
      require_relative "coverage/branching"

      cov_ladder(20)
      cov_ladder(7)
      cov_unless(nil)
      cov_ternary(2)
      cov_when(1)
      cov_in(1)
      cov_while(1)
      cov_until(0)
      cov_safe("a")
      cov_ops(1, 2)
      CovShapes.new.instance_one

      measured = Coverage.result.find { |path, _| File.basename(path) == "branching.rb" }.last
      measured[:branches].each do |root, sides|
        puts root.inspect
        sides.each { |side, count| puts "  #{side.inspect} => #{count}" }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:if, 0, 6, 2, 12, 5]
        [:then, 1, 7, 4, 7, 8] => 1
        [:else, 2, 8, 2, 12, 5] => 1
      [:if, 3, 8, 2, 12, 5]
        [:then, 4, 9, 4, 9, 8] => 1
        [:else, 5, 11, 4, 11, 10] => 0
      [:unless, 6, 16, 2, 16, 16]
        [:else, 7, 16, 2, 16, 16] => 0
        [:then, 8, 16, 2, 16, 7] => 1
      [:if, 9, 19, 21, 19, 43]
        [:then, 10, 19, 31, 19, 36] => 1
        [:else, 11, 19, 39, 19, 43] => 0
      [:case, 12, 22, 2, 26, 5]
        [:when, 13, 23, 14, 23, 18] => 1
        [:when, 14, 24, 14, 24, 18] => 0
        [:else, 15, 25, 7, 25, 13] => 0
      [:case, 16, 30, 2, 33, 5]
        [:in, 17, 31, 18, 31, 22] => 1
        [:in, 18, 32, 17, 32, 21] => 0
        [:else, 19, 30, 2, 33, 5] => 0
      [:while, 20, 37, 2, 39, 5]
        [:body, 21, 38, 4, 38, 10] => 1
      [:until, 22, 44, 2, 44, 21]
        [:body, 23, 44, 2, 44, 8] => 2
      [:"&.", 24, 48, 18, 48, 25]
        [:then, 25, 48, 18, 48, 25] => 1
        [:else, 26, 48, 18, 48, 25] => 0
      [:if, 27, 66, 0, 68, 3]
        [:then, 28, 67, 2, 67, 27] => 0
        [:else, 29, 66, 0, 68, 3] => 1
    OUT
  end

  it "names every method the way the C extension names it" do
    result = ze0(<<~'RUBY', files: beside("coverage/branching.rb"))
      # Method coverage over the AOT instrumentation, against the C
      # extension row for row. A row is made where the definition runs,
      # so it carries that run's owner and name and the span of the
      # `def` or the block behind it; the key is [owner, name, start
      # line, start column, end line, end column].
      #
      # branching.rb holds the shapes the rule turns on: an `attr_reader`
      # is no row, a `def` under a branch that never ran is absent, a
      # singleton def's owner is the singleton class, and
      # `define_method` is located at the block, not at the call. The
      # rows come out in the order the C extension walks the heap in, so
      # they are sorted here by where each one was written.
      require "coverage"
      Coverage.start(methods: true)
      require_relative "coverage/branching"

      cov_ladder(20)
      cov_ladder(7)
      cov_unless(nil)
      cov_ternary(2)
      cov_when(1)
      cov_in(1)
      cov_while(1)
      cov_until(0)
      cov_safe("a")
      cov_ops(1, 2)
      CovShapes.new.instance_one

      measured = Coverage.result.find { |path, _| File.basename(path) == "branching.rb" }.last
      measured[:methods].sort_by { |(owner, name, *where), _| [where, name.to_s, owner.to_s] }.each do |key, count|
        puts "#{key.inspect} => #{count}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [Object, :cov_ladder, 5, 0, 13, 3] => 2
      [Object, :cov_unless, 15, 0, 17, 3] => 1
      [Object, :cov_ternary, 19, 0, 19, 43] => 1
      [Object, :cov_when, 21, 0, 27, 3] => 1
      [Object, :cov_in, 29, 0, 34, 3] => 1
      [Object, :cov_while, 36, 0, 41, 3] => 1
      [Object, :cov_until, 43, 0, 46, 3] => 1
      [Object, :cov_safe, 48, 0, 48, 25] => 1
      [Object, :cov_ops, 51, 0, 51, 33] => 1
      [Object, :cov_uncalled, 53, 0, 53, 25] => 0
      [CovShapes, :instance_one, 56, 2, 56, 22] => 1
      [#<Class:CovShapes>, :singleton_one, 57, 2, 57, 28] => 0
      [CovShapes, :defined_one, 58, 30, 58, 35] => 0
      [CovMixin, :mixed_one, 63, 2, 63, 19] => 0
    OUT
  end
end
