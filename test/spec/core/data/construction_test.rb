# frozen_string_literal: true

require "spec_helper"

describe "Data: construction" do
  it "Data.new by position and by keyword raises for a missing, an extra or an unknown value" do
    result = zr(<<~'RUBY')
      # Data.new by position and by keyword, the errors for a missing, an
      # extra or an unknown value, and a frozen result.
      D = Data.define(:x, :y)
      p D.new(1, 2)
      p D.new(x: 1, y: 2)
      p D[3, 4]
      p D.new(y: 2, x: 1) == D.new(1, 2)
      p D.new(1, 2).frozen?
      begin
        D.new(1)
      rescue ArgumentError => e
        p e.message
      end
      begin
        D.new(1, 2, 3)
      rescue ArgumentError => e
        p e.message
      end
      begin
        D.new(x: 1)
      rescue ArgumentError => e
        p e.message
      end
      begin
        D.new(x: 1, y: 2, z: 3)
      rescue ArgumentError => e
        p e.message
      end
      begin
        D.new(1, y: 2)
      rescue ArgumentError => e
        p e.message
      end
      begin
        D.new(1, 2).instance_variable_set(:@z, 1)
      rescue FrozenError => e
        p e.class
      end
      E = Data.define
      p E.new
      h = { x: 5, y: 6 }
      p D.new(**h)
      p D.new(1, 2).with(y: 7)
    RUBY

    _(result).must_answer <<~'OUT'
      #<data D x=1, y=2>
      #<data D x=1, y=2>
      #<data D x=3, y=4>
      true
      true
      "missing keyword: :y"
      "wrong number of arguments (given 3, expected 0..2)"
      "missing keyword: :y"
      "unknown keyword: :z"
      "wrong number of arguments (given 2, expected 0)"
      FrozenError
      #<data E>
      #<data D x=5, y=6>
      #<data D x=1, y=7>
    OUT
  end

  it "a redefined initialize of a Data class gets keywords, also in a subclass" do
    result = zr(<<~'RUBY')
      # A redefined initialize of a Data class gets keywords, also from
      # values by position, and can give defaults; a subclass keeps it.
      D = Data.define(:x, :y) do
        def initialize(x:, y: 0)
          super
        end
      end
      p D.new(1)
      p D.new(x: 2)
      p D.new(1, 2)
      class E < D
        def initialize(x:, y: 9)
          super(x: x * 10, y: y)
        end
      end
      p E.new(1)
      p E.new(x: 2, y: 3)
      p E.new(1).frozen?
      F = Data.define(:a)
      class G < F; end
      p G.new(4)
      p G.new(a: 5).a
      p G.new(4) == F.new(4)
    RUBY

    _(result).must_answer <<~'OUT'
      #<data D x=1, y=0>
      #<data D x=2, y=0>
      #<data D x=1, y=2>
      #<data E x=10, y=9>
      #<data E x=20, y=3>
      true
      #<data G a=4>
      5
      false
    OUT
  end

  it "new takes String keys and refuses other keys" do
    result = zr(<<~'RUBY')
      P = Data.define(:x, :y)
      p P.new("x" => 1, "y" => 2), P.new("x" => 1, y: 2)
      [-> { P.new(1 => 1, 2 => 2) }, -> { P.new("x" => 1, "y" => 2, "z" => 3) }, -> { P.new(x: 1, "z" => 2) }].each do |f|
        f.call
      rescue ArgumentError, TypeError => e
        p [e.class, e.message]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      #<data P x=1, y=2>
      #<data P x=1, y=2>
      [TypeError, "1 is not a symbol nor a string"]
      [ArgumentError, "unknown keyword: \"z\""]
      [ArgumentError, "missing keyword: :y"]
    OUT
  end
end
