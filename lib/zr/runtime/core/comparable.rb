# frozen_string_literal: true

# Comparable over `<=>`.
module Comparable
  # A `<=>` that calls `==` (Kernel's does) returns nil, so the two
  # never call each other in a loop.
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

  def <(other) = Comparable.cmp(self, other) < 0
  def <=(other) = Comparable.cmp(self, other) <= 0
  def >(other) = Comparable.cmp(self, other) > 0
  def >=(other) = Comparable.cmp(self, other) >= 0

  # cmp_between: `<=>` against each bound, never the receiver's own
  # operators.
  def between?(low, high) = Comparable.cmp(self, low) >= 0 && Comparable.cmp(self, high) <= 0

  # One argument must be a Range, as cmp_clamp reads it; two are the
  # bounds, either of them nil.
  def clamp(low, high = (one = true))
    if one
      unless low.is_a?(Range)
        shown = case low
                when nil then +"nil"
                when true then +"true"
                when false then +"false"
                else low.class
                end
        raise TypeError, "wrong argument type #{shown} (expected Range)"
      end
      raise ArgumentError, +"cannot clamp with an exclusive range" if low.exclude_end? && !low.end.nil?

      high = low.end
      low = low.begin
    end
    if !low.nil? && !high.nil?
      c = low <=> high
      Primitive.zr_cmperr(low, high) if c.nil?
      raise ArgumentError, +"min argument must be less than or equal to max argument" if c > 0
    end
    return low if !low.nil? && Comparable.cmp(self, low) < 0
    return high if !high.nil? && Comparable.cmp(self, high) > 0

    self
  end

  # cmpint over `<=>`. It takes both sides, not self, so that a method
  # of Comparable bound to any object reports the comparison that failed.
  def self.cmp(left, right)
    Primitive.attr! :hidden
    plain = Primitive.zr_cmp_plain(left, right)
    return plain if plain

    c = left <=> right
    Primitive.zr_cmperr(left, right) if c.nil?

    c
  end
end

class Numeric
  include Comparable
end

class String
  include Comparable
end
