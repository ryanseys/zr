# frozen_string_literal: true

require "spec_helper"

describe "Prime programs" do
  it "Prime.first, Integer#prime? and prime_division each answer" do
    result = ze0(<<~'RUBY')
      require "prime"

      p Prime.first(5)
      p 7.prime?
      p Prime.prime_division(12)
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 3, 5, 7, 11]
      true
      [[2, 2], [3, 1]]
    OUT
  end
end
