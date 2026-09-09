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

  def clamp(low, high = nil)
    if high.nil? && low.is_a?(Range)
      raise ArgumentError, "cannot clamp with an exclusive range" if low.exclude_end? && !low.end.nil?

      high = low.end
      low = low.begin
    end
    raise ArgumentError, "min argument must be less than or equal to max argument" if !low.nil? && !high.nil? && (low <=> high) > 0
    return low if !low.nil? && self < low
    return high if !high.nil? && self > high

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
