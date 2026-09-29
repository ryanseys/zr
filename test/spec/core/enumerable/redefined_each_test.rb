# frozen_string_literal: true

require "spec_helper"

describe "Enumerable: a redefined each" do
  it "the core walks its own Arrays and Hashes without a program's each, as ruby's C does" do
    result = zr(<<~'RUBY')
      # Ruby's C walks its own Arrays and Hashes directly, so a program's
      # `each` runs only where ruby sends it by name.
      $calls = 0
      module CountEach
        def each(*, &) = ($calls += 1; super)
      end
      [Array, Hash, Range, Struct].each { |klass| klass.prepend(CountEach) }
      Point = Struct.new(:x, :y)
      sink = Object.new
      def sink.write(*parts) = parts.sum(&:size)
      checks = {
        "puts" => -> { $stdout = sink; puts [1, [2]], "a"; $stdout = STDOUT },
        "print" => -> { $stdout = sink; print "a", "b"; $stdout = STDOUT },
        "p" => -> { $stdout = sink; p 1, [2]; $stdout = STDOUT },
        "warn" => -> { $stderr = sink; warn "a", ["b"]; $stderr = STDERR },
        "pack" => -> { [1, 2].pack("CU") },
        "regexp" => -> { Regexp.new("[a-z]+\\d{2,}") },
        "join" => -> { File.join("a", ["b", "c"]) },
        "glob" => -> { Dir.glob([File.join(__dir__, "*"), __dir__]) { } },
        "sort_by!" => -> { [1].sort_by! { _1 } },
        "hash []" => -> { Hash[1, 2, 3, 4] },
        "values_at" => -> { [1, 2, 3].values_at(0, 1..2) },
        "union" => -> { [1].union([2], [3]); [1, 2].intersection([2], [2, 3]) },
        "literal min" => -> { x = 2; [x, 1, 3].min + [x, 1].max },
        "marshal" => -> { Marshal.load(Marshal.dump([Point.new(1, 2), 2**70])) },
        "match inspect" => -> { /(?<a>x)(y)?/.match("x").inspect },
        "proc inspect" => -> { proc { |a, b = 1, *c, d:, &e| }.inspect },
        "each_pair" => -> { Point.new(1, 2).each_pair { } },
        "eval" => -> { eval("[1, 2].map { |v| v + 1 }.sum") },
      }
      checks.each do |name, check|
        before = $calls
        check.call
        $stdout.write("#{name}: #{$calls - before}\n")
      end
    RUBY

    _(result).must_answer <<~'OUT'
      puts: 0
      print: 0
      p: 0
      warn: 0
      pack: 0
      regexp: 0
      join: 0
      glob: 0
      sort_by!: 0
      hash []: 0
      values_at: 0
      union: 0
      literal min: 0
      marshal: 0
      match inspect: 0
      proc inspect: 0
      each_pair: 0
      eval: 0
    OUT
  end

  it "a program's each runs where ruby's C sends each by name" do
    result = zr(<<~'RUBY')
      # Where ruby's C sends `each` by name (rb_block_call), a program's
      # `each` runs, once for each walk.
      $calls = 0
      module CountEach
        def each(*, &) = ($calls += 1; super)
      end
      [Array, Hash, Range].each { |klass| klass.prepend(CountEach) }
      checks = {
        "each_slice" => -> { [1, 2, 3].each_slice(2).to_a },
        "inject" => -> { [1, 2].inject(:+) },
        "zip hash" => -> { [1, 2].zip({ a: 1 }) },
        "lazy map" => -> { [1, 2].lazy.map { _1 * 2 }.to_a },
        "lazy flat_map" => -> { [1, 2].lazy.flat_map { [_1, _1] }.first(3) },
        "range first" => -> { (1..5).first(2); (1..5).first(0) },
        "chain" => -> { [1].chain([2]).to_a },
        "enumerator +" => -> { ([1].each + [2]).to_a },
        "hash map" => -> { { a: 1 }.map { _1 } },
        "set merge" => -> { Set[1].merge({ c: 1 }) },
        "sort_by!" => -> { [2, 1].sort_by! { _1 } },
      }
      checks.each do |name, check|
        before = $calls
        check.call
        $stdout.write("#{name}: #{$calls - before}\n")
      end
    RUBY

    _(result).must_answer <<~'OUT'
      each_slice: 1
      inject: 1
      zip hash: 1
      lazy map: 1
      lazy flat_map: 1
      range first: 2
      chain: 2
      enumerator +: 3
      hash map: 1
      set merge: 1
      sort_by!: 1
    OUT
  end

  it "a Set subclass's layer sends each by name, as its Ruby does" do
    result = zr(<<~'RUBY')
      # A direct subclass of Set takes the compatibility layer that CRuby
      # writes in Ruby, whose walks send each by name.
      $calls = 0
      module CountEach
        def each(*, &) = ($calls += 1; super)
      end
      [Array, Hash].each { |klass| klass.prepend(CountEach) }
      class MySet < Set; end
      set = MySet.new([1, 2])
      counts = [$calls]
      set.merge([3], { 4 => 5 })
      counts << $calls
      set & [1, 9]
      counts << $calls
      MySet.new([[1]]).flatten
      counts << $calls
      p counts, set.size
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 5, 6, 8]
      4
    OUT
  end
end
