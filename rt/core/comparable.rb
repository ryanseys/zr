# Comparable over `<=>`.
module Comparable
  # A `<=>` that comes back to `==` (Kernel's does) answers nil, so the
  # two never chase each other.
  def ==(other)
    return true if equal?(other)
    return false if Primitive.zr_recursive_enter(self, :==)

    begin
      c = self <=> other
      !c.nil? && c == 0
    ensure
      Primitive.zr_recursive_leave(self, :==)
    end
  end

  def <(other) = compare_to(other) < 0
  def <=(other) = compare_to(other) <= 0
  def >(other) = compare_to(other) > 0
  def >=(other) = compare_to(other) >= 0

  def between?(low, high) = self >= low && self <= high

  # One argument must be a Range, as cmp_clamp reads it; two are the
  # bounds, either of them nil.
  def clamp(low, high = (one = true))
    if one
      unless low.is_a?(Range)
        shown = case low
                when nil then "nil"
                when true then "true"
                when false then "false"
                else low.class
                end
        raise TypeError, "wrong argument type #{shown} (expected Range)"
      end
      raise ArgumentError, "cannot clamp with an exclusive range" if low.exclude_end? && !low.end.nil?

      high = low.end
      low = low.begin
    end
    if !low.nil? && !high.nil?
      c = low <=> high
      Primitive.zr_cmperr(low, high) if c.nil?
      raise ArgumentError, "min argument must be less than or equal to max argument" if c > 0
    end
    return low if !low.nil? && compare_to(low) < 0
    return high if !high.nil? && compare_to(high) > 0

    self
  end

  private

  def compare_to(other)
    Primitive.attr! :hidden
    c = self <=> other
    Primitive.zr_cmperr(self, other) if c.nil?

    c
  end
end

class Numeric
  include Comparable
end

class String
  include Comparable
end
