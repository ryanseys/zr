# frozen_string_literal: true

require "spec_helper"

describe "Math programs" do
  it "a Math function reads its argument through to_f, and the refusal names no function" do
    result = ze0(<<~'RUBY')
      # Math's functions read a Float, an Integer or another Numeric through
      # its to_f, and refuse anything else with ruby's message, whatever
      # answers to_f: the check names no function.
      class Lengthy
        def to_f = 2.0
      end
      class Measure < Numeric
        def to_f = 2.0
      end
      p Math.sin(0), Math.sqrt(16), Math.sqrt(2**70).class, Math.cos(1.0).round(3), Math.log(Measure.new).round(3), Math.hypot(3, 4)
      p (Math.log(Lengthy.new) rescue [$!.class, $!.message]), (Math.sin(nil) rescue [$!.class, $!.message]), (Math.sqrt("4") rescue [$!.class, $!.message])
      p (Math.cos(:a) rescue [$!.class, $!.message]), (Math.sqrt(-1) rescue [$!.class, $!.message]), (Math.atan2(nil, 1) rescue [$!.class, $!.message])
      p Math.exp(0), Math.cbrt(27), Math.sin(2**62).finite?, Math.sqrt(Rational(1, 4)), Math.log2(8), Math.log10(1000), Math.log(8, 2), (Math.log(-1) rescue $!.class)
      sum = 0.0
      1.upto(200_000) { |i| sum += Math.sin(i) * Math.cos(i) + 1.0 / Math.sqrt(i) }
      p sum.round(6)

    RUBY

    _(result).must_answer <<~'OUT'
      0.0
      4.0
      Float
      0.54
      0.693
      5.0
      [TypeError, "can't convert Lengthy into Float"]
      [TypeError, "can't convert nil into Float"]
      [TypeError, "can't convert String into Float"]
      [TypeError, "can't convert Symbol into Float"]
      [Math::DomainError, "Numerical argument is out of domain - sqrt"]
      [TypeError, "can't convert nil into Float"]
      1.0
      3.0
      true
      0.5
      3.0
      3.0
      3.0
      Math::DomainError
      892.933959
    OUT
  end

  it "a Float or an Integer argument is answered by the kernel at once, with the domain and the edges kept" do
    result = ze0(<<~'RUBY')
      # Math.sqrt, sin, cos, tan, atan, exp and cbrt answer a Float or a
      # fixnum with no send of the check: the domain refusal, -0.0, an
      # integer past 2**53, a negative integer and a bignum answer as
      # ruby does, and a redefinition of the function is what runs.
      p Math.sqrt(-0.0), Math.sqrt(0), Math.sqrt(1 << 62), Math.sqrt(9223372036854775807), Math.sqrt(Float::MAX), Math.sqrt(Float::INFINITY), Math.sqrt(Float::NAN).nan?
      p Math.sin(1 << 61), Math.exp(-1000), Math.cbrt(-8), Math.tan(1), Math.atan(1).round(6), Math.cos(0)
      p (Math.sqrt(-1.5) rescue $!.message), (Math.sqrt(-(1 << 62)) rescue $!.message), (Math.sin("1") rescue $!.message), (Math.exp(Rational(1, 2)) rescue $!.message).round(6)
      module Math
        remove_method :sqrt
        def self.sqrt(x) = :mine
      end
      p Math.sqrt(4)
    RUBY

    _(result).must_answer <<~'OUT'
      0.0
      0.0
      2147483648.0
      3037000499.97605
      1.3407807929942596e+154
      Infinity
      true
      0.9250044602531619
      0.0
      -2.0
      1.557407724654902
      0.785398
      1.0
      "Numerical argument is out of domain - sqrt"
      "Numerical argument is out of domain - sqrt"
      "can't convert String into Float"
      1.648721
      :mine
    OUT
  end
end
