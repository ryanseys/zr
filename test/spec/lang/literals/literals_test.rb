# frozen_string_literal: true

require "spec_helper"

describe "Literals programs" do
  it "hash literal with a splat raises from a later keys hash" do
    result = ze0(<<~'RUBY')
      # A hash literal that carries `**` stores its other pairs one by one;
      # a key whose `hash` raises must raise from the literal, not leave the
      # literal with no value.
      k = Object.new
      def k.hash = raise("boom")
      begin
        p({**{}, k => 1})
      rescue => e
        p [e.class, e.message]
      end
      begin
        p({**{a: 1}, k => 1}.size)
      rescue => e
        p [e.class, e.message]
      end
      p({**{a: 1}, b: 2})

    RUBY

    _(result).must_answer <<~'OUT'
      [RuntimeError, "boom"]
      [RuntimeError, "boom"]
      {a: 1, b: 2}
    OUT
  end

  it "range of integer literals is one frozen object per site" do
    result = ze0(<<~'RUBY')
      def ids = 3.times.map { yield.object_id }.uniq.size

      p ids { (1..2) }
      p ids { (1...2) }
      p ids { (1..) }
      p ids { (..-3) }
      p ids { (nil..nil) }
      p ids { (1..2**70) }
      p (1..2).frozen?, (1..2).equal?(1..2)

      x = 1
      p ids { (x..2) }
      p ids { ("a".."b") }
      p ids { (1.0..2) }
      p ids { (1..2.0) }
      p ids { (:a..:b) }

      def r = (3..4)
      p r.equal?(r)
      p Range.new(1, 2).frozen?, Range.new(1, 2).equal?(Range.new(1, 2))

    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      1
      1
      1
      3
      true
      false
      3
      3
      3
      3
      3
      true
      true
      false
    OUT
  end
end
