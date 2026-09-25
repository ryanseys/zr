# frozen_string_literal: true

require "spec_helper"

describe "Struct: construction" do
  it "Struct.new by position leaves nil, raises for more, and binds keywords by keyword_init" do
    result = zr(<<~'RUBY')
      # Struct#initialize by position: fewer values leave nil, more raise,
      # keywords bind by name, and each keyword_init: form keeps its rule.
      P = Struct.new(:a, :b, :c)
      p P.new.to_a
      p P.new(1).to_a
      p P.new(1, 2, 3).to_a
      begin
        P.new(1, 2, 3, 4)
      rescue ArgumentError => e
        p e.message
      end
      p P.new(a: 1, c: 3).to_a
      p P.new(1, b: 2).to_a
      begin
        P.new(d: 1)
      rescue ArgumentError => e
        p e.message
      end
      K = Struct.new(:a, :b, keyword_init: true)
      p K.new(a: 1).to_a
      p K.new.to_a
      begin
        K.new(1)
      rescue ArgumentError => e
        p e.message
      end
      F = Struct.new(:a, :b, keyword_init: false)
      p F.new(a: 1).to_a
      p P[4, 5].to_a
      o = P.new(1, 2, 3)
      o.send(:initialize, 7)
      p o.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [nil, nil, nil]
      [1, nil, nil]
      [1, 2, 3]
      "struct size differs"
      [1, nil, 3]
      [1, {b: 2}, nil]
      "unknown keywords: d"
      [1, nil]
      [nil, nil]
      "wrong number of arguments (given 1, expected 0)"
      [{a: 1}, nil]
      [4, 5, nil]
      [7, nil, nil]
    OUT
  end

  it "a redefined initialize or new of a Struct runs, also in a subclass of a subclass" do
    result = zr(<<~'RUBY')
      # A redefined initialize runs, with or without super, in a subclass of
      # a subclass too, and a redefined `new` runs in place of Class#new.
      P = Struct.new(:a, :b)
      class Q < P
        def initialize(a)
          super(a, a * 2)
        end
      end
      class R < Q
        def initialize
          super(5)
        end
      end
      p Q.new(3).to_a
      p R.new.to_a
      p R.new == Q.new(5)
      p R.new.b
      N = Struct.new(:x) do
        def initialize(*) = nil
      end
      p N.new(1).x
      M = Struct.new(:x) do
        def self.new(*args) = "new #{args.inspect}"
      end
      p M.new(1)
      S = Struct.new(:x, :y)
      class S
        def initialize(x, y = x) = super
      end
      p S.new(1).to_a
      s = S.new(1, 2)
      s.y = 9
      p [s.x, s.y, s[1], s.to_a]
      s.freeze
      begin
        s.x = 3
      rescue FrozenError => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 6]
      [5, 10]
      false
      10
      nil
      "new [1]"
      [1, 1]
      [1, 9, 9, [1, 9]]
      FrozenError
    OUT
  end

  it "keywords to a Struct bind by name, and a keyword that is not a member raises" do
    result = zr(<<~'RUBY')
      # Keywords bind by name where the class takes them: every member,
      # some members, none, and a keyword that is not a member.
      K = Struct.new(:a, :b, :c, keyword_init: true)
      p K.new(a: 1, b: 2, c: 3).to_a
      p K.new(c: 3).to_a
      p K.new(**{}).to_a
      h = { b: 5 }
      p K.new(**h).to_a
      begin
        K.new(a: 1, z: 2)
      rescue ArgumentError => e
        p e.message
      end
      N = Struct.new(:a, :b)
      p N.new(b: 2).to_a
      begin
        N.new(a: 1, zz: 2)
      rescue ArgumentError => e
        p e.message
      end
      F = Struct.new(:a, :b, keyword_init: false)
      p F.new(a: 1, b: 2).to_a
      class Sub < K
        def with(**over) = Sub.new(**to_h, **over)
      end
      p Sub.new(a: 1).with(b: 7).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [nil, nil, 3]
      [nil, nil, nil]
      [nil, 5, nil]
      "unknown keywords: z"
      [nil, 2]
      "unknown keywords: zz"
      [{a: 1, b: 2}, nil]
      [1, 7, nil]
    OUT
  end
end
