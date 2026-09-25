# frozen_string_literal: true

require "spec_helper"

# A `case` whose `when` values are six or more constant paths selects its
# arm from a table keyed on the subject's class (`Control#class_case`).
# Each program runs the same site many times, so the table is full when
# the program changes the state that the table depends on.
describe "Case dispatch programs" do
  it "selects arms for subclasses modules extend and singleton classes" do
    result = zr(<<~'RUBY')
      module Tag; end
      class A; end
      class B < A; end
      class C; include Tag; end
      class D; end
      class E; end
      class F; end
      class G < F; end

      def kind(x)
        case x
        when B then "B"
        when A then "A"
        when Tag then "Tag"
        when D, E then "D or E"
        when F then "F"
        when Comparable then "Comparable"
        else "other"
        end
      end

      d = D.new
      e = E.new
      tagged = E.new
      tagged.extend(Tag)
      single = F.new
      def single.hi = 1
      subjects = [A.new, B.new, C.new, d, e, G.new, single, tagged, 1, "s", nil, true, :sym, 1.5, [], {}]
      3.times do
        puts subjects.map { |s| kind(s) }.join(" ")
      end
      later = D.new
      later.extend(Tag)
      puts kind(later)
      puts kind(d)
    RUBY

    _(result).must_answer <<~'OUT'
      A B Tag D or E D or E F F Tag Comparable Comparable other other Comparable Comparable other other
      A B Tag D or E D or E F F Tag Comparable Comparable other other Comparable Comparable other other
      A B Tag D or E D or E F F Tag Comparable Comparable other other Comparable Comparable other other
      Tag
      D or E
    OUT
  end

  it "follows Module#=== and a class === defined in the loop" do
    result = zr(<<~'RUBY')
      class A; end
      class B; end
      class C; end
      class D; end
      class E; end
      class F; end

      def kind(x)
        case x
        when A then :a
        when B then :b
        when C then :c
        when D then :d
        when E then :e
        when F then :f
        else :none
        end
      end

      objs = [A.new, B.new, C.new, D.new, E.new, F.new, 7]
      out = []
      6.times do |i|
        if i == 2
          class B
            def self.===(o) = o == 7
          end
        end
        if i == 4
          class Module
            alias_method :old_eqq, :===
            def ===(o) = name == "A" ? o.is_a?(E) : old_eqq(o)
          end
        end
        out << objs.map { |o| kind(o) }.join(",")
      end
      puts out
    RUBY

    _(result).must_answer <<~'OUT'
      a,b,c,d,e,f,none
      a,b,c,d,e,f,none
      a,none,c,d,e,f,b
      a,none,c,d,e,f,b
      none,none,c,d,a,f,b
      none,none,c,d,a,f,b
    OUT
  end

  it "follows a prepended === and a reassigned or const_set constant" do
    result = zr(<<~'RUBY')
      class A; end
      class B; end
      class C; end
      class D; end
      class E; end
      class F; end

      def kind(x)
        case x
        when A then "A"
        when B then "B"
        when C then "C"
        when D then "D"
        when E then "E"
        when F then "F"
        else "else"
        end
      end

      a = A.new
      b = B.new
      e = E.new
      5.times do |i|
        case i
        when 1
          $VERBOSE = nil
          Object.const_set(:A, B)
        when 2
          Object.const_set(:C, E)
        when 3
          C.singleton_class.prepend(Module.new { def ===(o) = false })
        end
        puts [kind(a), kind(b), kind(e)].join(" ")
      end
    RUBY

    _(result).must_answer <<~'OUT'
      A B E
      else A E
      else A C
      else A else
      else A else
    OUT
  end

  it "tests a Range and an object with its own === in the arms" do
    result = zr(<<~'RUBY')
      class Even
        def ===(o) = o.is_a?(Integer) && o.even?
      end
      SMALL = 1..3
      EVEN = Even.new
      class A; end
      class B; end
      class C; end
      class D; end

      def kind(x)
        case x
        when A then "A"
        when SMALL then "small"
        when EVEN then "even"
        when B, C then "B or C"
        when D then "D"
        else "else"
        end
      end

      3.times do
        puts [A.new, 2, 3, 4, 5, B.new, C.new, D.new, "x", nil].map { |x| kind(x) }.join(" ")
      end
    RUBY

    _(result).must_answer <<~'OUT'
      A small small even else B or C B or C D else else
      A small small even else B or C B or C D else else
      A small small even else B or C B or C D else else
    OUT
  end

  it "keeps its answers through a collection and many classes" do
    result = zr(<<~'RUBY')
      class A; end
      class B; end
      class C; end
      class D; end
      class E; end
      class F; end
      KLASSES = Array.new(80) { |i| Class.new(i.even? ? A : B) }

      def kind(x)
        case x
        when C then "C"
        when D then "D"
        when E then "E"
        when F then "F"
        when A then "A"
        when B then "B"
        else "else"
        end
      end

      counts = Hash.new(0)
      4.times do |round|
        KLASSES.each { |k| counts[kind(k.new)] += 1 }
        [C, D, E, F].each { |k| counts[kind(k.new)] += 1 }
        GC.start
        tmp = Class.new(C)
        counts[kind(tmp.new)] += 1
        counts[kind(round)] += 1
      end
      p counts
    RUBY

    _(result).must_answer <<~'OUT'
      {"A" => 160, "B" => 160, "C" => 8, "D" => 4, "E" => 4, "F" => 4, "else" => 4}
    OUT
  end

  it "runs nested cases" do
    result = zr(<<~'RUBY')
      class A; end
      class B; end
      class C; end
      class D; end
      class E; end
      class F; end

      def inner(y)
        case y
        when A then 1
        when B then 2
        when C then 3
        when D then 4
        when E then 5
        when F then 6
        end
      end

      def outer(x, y)
        case x
        when A then [:a, inner(y)]
        when B then [:b, inner(y)]
        when C then [:c, inner(y)]
        when D then [:d, case y when A, B, C, D, E, F then :any end]
        when E then [:e, inner(y)]
        when F then [:f, inner(y)]
        else [:none, inner(y)]
        end
      end

      objs = [A.new, B.new, C.new, D.new, E.new, F.new, 0]
      3.times do
        p objs.map { |x| outer(x, objs[(objs.index(x) + 3) % objs.size]) }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [[:a, 4], [:b, 5], [:c, 6], [:d, nil], [:e, 1], [:f, 2], [:none, 3]]
      [[:a, 4], [:b, 5], [:c, 6], [:d, nil], [:e, 1], [:f, 2], [:none, 3]]
      [[:a, 4], [:b, 5], [:c, 6], [:d, nil], [:e, 1], [:f, 2], [:none, 3]]
    OUT
  end

  it "gives TracePoint each === call of the arms" do
    result = zr(<<~'RUBY')
      class A; end
      class B; end
      class C; end
      class D; end
      class E; end
      class F; end

      def kind(y)
        case y
        when A then 1
        when B then 2
        when C then 3
        when D then 4
        when E then 5
        when F then 6
        end
      end

      3.times { kind(D.new) }
      calls = []
      tp = TracePoint.new(:c_call) { |t| calls << t.method_id if t.method_id == :=== }
      tp.enable
      kind(D.new)
      kind(1)
      tp.disable
      p calls.size
    RUBY

    _(result).must_answer <<~'OUT'
      10
    OUT
  end
end
