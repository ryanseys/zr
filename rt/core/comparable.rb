# Comparable over `<=>`.
module Comparable
  def ==(other)
    return true if equal?(other)

    c = self <=> other
    !c.nil? && c == 0
  end

  def <(other) = compare_to(other) < 0
  def <=(other) = compare_to(other) <= 0
  def >(other) = compare_to(other) > 0
  def >=(other) = compare_to(other) >= 0

  def between?(low, high) = self >= low && self <= high

  def clamp(low, high)
    return low if self < low
    return high if self > high

    self
  end

  private

  def compare_to(other)
    c = self <=> other
    raise ArgumentError, "comparison of #{self.class} with #{other.inspect} failed" if c.nil?

    c
  end
end

class Numeric
  include Comparable
end

class String
  include Comparable
end
