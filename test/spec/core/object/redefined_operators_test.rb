# frozen_string_literal: true

require "spec_helper"

describe "Object: redefined operators" do
  it "Array, Integer and Enumerable methods call a redefined operator as often as ruby's C does" do
    result = zr(<<~'RUBY')
      # The core's own methods call a redefined operator exactly as often as
      # ruby's C does: through rb_equal, rb_eql and OPTIMIZED_CMP where it
      # dispatches, and never where it compares natively.
      SEEN = []
      $busy = true
      TARGETS = { Integer => %i[== <=> < <= > >= eql? hash + -], String => %i[== <=> eql? hash], Symbol => %i[== <=>], Float => %i[== <=> <] }
      TARGETS.each do |klass, ops|
        ops.each do |op|
          original = klass.instance_method(op)
          tag = "#{klass}##{op}"
          klass.define_method(op) do |*args|
            SEEN << tag unless $busy
            original.bind_call(self, *args)
          end
        end
      end
      $VERBOSE = nil
      def run(label)
        SEEN.clear
        $busy = false
        yield
        $busy = true
        puts "#{label}: #{SEEN.tally.sort.map { |tag, n| "#{tag}=#{n}" }.join(' ')}"
      end
      a = [3, 1, 2, 5, 4]
      s = %w[b a c]
      y = %i[b a c]
      run("ary ==") { [1, 2, 3] == [1, 2, 3] }
      run("ary include") { a.include?(4) }
      run("ary index") { a.index(5); a.rindex(1) }
      run("ary delete") { a.dup.delete(2) }
      run("ary count") { a.count(2) }
      run("ary uniq") { [1, 1, 2].uniq }
      run("ary -") { a - [1, 2] }
      run("ary &") { a & [1, 2] }
      run("ary sort") { a.sort }
      run("ary sort str") { s.sort }
      run("ary sort sym") { y.sort }
      run("ary min max") { a.min; a.max; a.minmax }
      run("ary sum") { a.sum }
      run("ary assoc") { [[1, 2], [3, 4]].assoc(3); [[1, 2], [3, 4]].rassoc(4) }
      run("ary hash") { a.hash }
      run("ary eql") { a.eql?(a.dup) }
      run("hash lookup") { h = { 1 => 2, "x" => 3, :y => 4 }; h[1]; h["x"]; h[:y] }
      run("hash ==") { { 1 => 2 } == { 1 => 2 } }
      run("hash value?") { { 1 => 2 }.value?(2); { 1 => 2 }.key(2) }
      run("range each") { (1..5).each { } }
      run("range include") { (1..5).include?(3); (1..5) === 3; (1..5).cover?(3) }
      run("range ==") { (1..2) == (1..2) }
      run("int times") { 5.times { } }
      run("int upto") { 1.upto(5) { }; 5.downto(1) { } }
      run("int step") { 1.step(10, 3) { } }
      run("int between") { 3.between?(1, 5); 3.clamp(1, 5) }
      run("str ==") { "a" == "a"; "a".eql?("a") }
      run("str cmp") { "a" <=> "b" }
      run("str case") { case "b" when "a" then 1 when "b" then 2 end }
      run("int case") { case 3 when 1 then 1 when 3 then 2 end }
      run("sym case") { case :b when :a then 1 when :b then 2 end }
      run("struct ==") { S = Struct.new(:a) unless defined?(S); S.new(1) == S.new(1) }
      run("sort_by") { a.sort_by { -_1 } }
      run("min_by") { a.min_by { _1 } }
      run("group_by") { a.group_by(&:odd?) }
      run("tally") { [1, 1, 2].tally }
      run("each_with_index") { a.each_with_index { } }
      run("inject") { a.inject(:+) }
      run("zip flatten") { a.zip(a).flatten }
      run("str split") { "a,b,c".split(",") }
      run("format") { format("%d %s", 1, "a") }
      run("set") { require "set"; Set[1, 2, 3].include?(2) }
    RUBY

    _(result).must_answer <<~'OUT'
      ary ==: 
      ary include: Integer#===4
      ary index: Integer#===6
      ary delete: Integer#===4
      ary count: Integer#===4
      ary uniq: 
      ary -: Integer#===7 Integer#eql?=7
      ary &: Integer#===8 Integer#eql?=8
      ary sort: Integer#<=>=6
      ary sort str: String#<=>=2
      ary sort sym: Symbol#<=>=2
      ary min max: Integer#<=>=16
      ary sum: 
      ary assoc: Integer#===2
      ary hash: 
      ary eql: 
      hash lookup: 
      hash ==: 
      hash value?: 
      range each: 
      range include: Integer#<=>=6
      range ==: 
      int times: Integer#<=6
      int upto: 
      int step: Integer#===2 Integer#>=1
      int between: Integer#<=>=5
      str ==: String#===1 String#eql?=1
      str cmp: String#<=>=1
      str case: 
      int case: 
      sym case: 
      struct ==: 
      sort_by: Integer#<=>=10
      min_by: Integer#<=>=4
      group_by: 
      tally: 
      each_with_index: 
      inject: Integer#+=4
      zip flatten: 
      str split: 
      format: 
      set: 
    OUT
  end

  it "Hash, String, Symbol, Float, Range and the core's own arithmetic call a redefined operator as ruby's C does" do
    result = zr(<<~'RUBY')
      # The same count for Hash, String, Symbol, Float, Range, Struct and
      # Data methods, and for the core's own arithmetic and formatting.
      SEEN = []
      $busy = true
      TARGETS = { Integer => %i[== <=> < <= > >= eql? hash + -], String => %i[== <=> eql? hash], Symbol => %i[== <=>], Float => %i[== <=> <] }
      TARGETS.each do |klass, ops|
        ops.each do |op|
          original = klass.instance_method(op)
          tag = "#{klass}##{op}"
          klass.define_method(op) do |*args|
            SEEN << tag unless $busy
            original.bind_call(self, *args)
          end
        end
      end
      $VERBOSE = nil
      def run(label)
        SEEN.clear
        $busy = false
        yield
        $busy = true
        puts "#{label}: #{SEEN.tally.sort.map { |tag, n| "#{tag}=#{n}" }.join(' ')}"
      end
      h = { 1 => 2, 3 => 4 }
      s = %w[b a c]
      y = %i[b a c]
      f = [1.5, 0.5, 2.5]
      run("hash value? key") { h.value?(4); h.key(4); h.rassoc(4) }
      run("hash eql hash") { h.eql?({ 1 => 2, 3 => 4 }); h.hash }
      run("hash str keys") { g = { "a" => 1 }; g["a"]; g.key?("a"); g.merge("b" => 2) }
      run("hash compare_by_identity") { g = {}.compare_by_identity; g[1] = 2; g[1] }
      run("ary uniq str") { %w[a b a].uniq }
      run("ary uniq block") { [1, 2, 3].uniq(&:odd?) }
      run("ary <=>") { [1, 2] <=> [1, 3]; s <=> s.dup }
      run("ary max str") { s.max; s.min; s.minmax }
      run("ary sort floats") { f.sort; f.max }
      run("ary include str") { s.include?("c"); s.index("c") }
      run("ary include sym") { y.include?(:c); y.index(:c) }
      run("ary difference") { [1, 2, 3].difference([2]); [1, 2].union([3]); [1, 2].intersect?([2]) }
      run("ary flatten uniq") { [[1, 2], [2, 3]].flatten.uniq }
      run("ary sum floats") { f.sum }
      run("ary product") { [1, 2].product([3]) }
      run("ary bsearch") { [1, 2, 3, 4].bsearch { |x| x >= 3 } }
      run("ary fill rotate") { [1, 2, 3].rotate(1); Array.new(3, 0) }
      run("enum include") { (1..5).each_slice(2).to_a; (1..3).include?(2); [1, 2].each_entry.include?(2) }
      run("enum min_by str") { s.min_by(&:itself); s.max_by(&:itself); s.sort_by(&:itself) }
      run("enum sum") { (1..4).sum; (1..4).reduce(1) { _1 * _2 } }
      run("enum each_cons") { (1..5).each_cons(2).to_a }
      run("enum zip chunk") { [1, 1, 2].chunk_while { _1 == _2 }.to_a }
      run("str ==") { "abc" == "abd"; "abc".eql?("abc"); "abc".equal?("abc") }
      run("str start end") { "abc".start_with?("a"); "abc".end_with?("c"); "abc".include?("b") }
      run("str sub gsub") { "abc".sub("b", "x"); "abc".gsub("b", "x"); "a-b".split("-") }
      run("str cmp casecmp") { "a" <=> "b"; "a".casecmp("B"); "a".casecmp?("A") }
      run("str succ upto") { "a".upto("c") { } }
      run("str hash") { "a".hash; { "x" => 1 }["x"] }
      run("sym cmp") { :a <=> :b; :a == :b; y.sort }
      run("float cmp") { 1.5 <=> 2.5; 1.5 == 1.5; 1.5 < 2.5; f.min }
      run("float round") { 1.25.round(1); 2.5.floor; 3.7.ceil }
      run("int pow gcd") { 2**10; 12.gcd(8); 12.lcm(8); 10.digits }
      run("int to_s") { 255.to_s(16); 255.to_s(2); Integer("42") }
      run("rational") { Rational(1, 2) + Rational(1, 3); 1r == 1 }
      run("comparable clamp") { 5.clamp(1, 3); "b".between?("a", "c") }
      run("struct eql hash") { S2 = Struct.new(:a) unless defined?(S2); S2.new(1).eql?(S2.new(1)); S2.new(1).hash }
      run("data ==") { D2 = Data.define(:a) unless defined?(D2); D2.new(a: 1) == D2.new(a: 1) }
      run("range step") { (1..10).step(3).to_a; (1..10).step(3) { } }
      run("range each str") { ("a".."c").each { } }
      run("range minmax") { (1..5).minmax; (1..5).sum; (1..5).to_a }
      run("set ops") { require "set"; (Set[1, 2] | Set[3]); Set[1, 2].subset?(Set[1, 2, 3]) }
      run("case str") { case "b" when "a", "b" then 1 end }
      run("hash each") { h.each { }; h.sort; h.min_by { _2 } }
      run("pack") { [1, 2].pack("C*"); "ab".unpack("C*") }
      run("time") { Time.at(0).year; Time.at(0) <=> Time.at(1) }
      run("format float") { format("%.2f %05d %x", 1.5, 3, 255) }
      run("inspect") { [1, "a", :b, 1.5, nil].inspect; { a: 1 }.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      hash value? key: Integer#===3
      hash eql hash: 
      hash str keys: 
      hash compare_by_identity: 
      ary uniq str: 
      ary uniq block: 
      ary <=>: Integer#<=>=2 String#<=>=3
      ary max str: String#<=>=8
      ary sort floats: Float#<=>=4
      ary include str: String#===6
      ary include sym: Symbol#===4
      ary difference: Integer#===6 Integer#eql?=6
      ary flatten uniq: 
      ary sum floats: 
      ary product: 
      ary bsearch: Integer#>==2
      ary fill rotate: 
      enum include: Integer#<=>=2 Integer#===1
      enum min_by str: String#<=>=6
      enum sum: 
      enum each_cons: 
      enum zip chunk: Integer#===2
      str ==: String#===1 String#eql?=1
      str start end: 
      str sub gsub: 
      str cmp casecmp: String#<=>=1
      str succ upto: 
      str hash: String#hash=1
      sym cmp: Symbol#<=>=3 Symbol#===1
      float cmp: Float#<=1 Float#<=>=3 Float#===1
      float round: 
      int pow gcd: Integer#<=1
      int to_s: 
      rational: 
      comparable clamp: Integer#<=>=3 String#<=>=2
      struct eql hash: 
      data ==: 
      range step: Integer#<=1 Integer#===3 Integer#>==5
      range each str: String#<=>=1
      range minmax: Integer#<=>=2
      set ops: 
      case str: 
      hash each: Integer#<=>=2
      pack: 
      time: 
      format float: 
      inspect: 
    OUT
  end
end
