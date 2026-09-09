# Integer over the kernel's arithmetic.
class Integer
  def odd?
    self % 2 == 1
  end

  def even?
    self % 2 == 0
  end

  def zero?
    self == 0
  end

  def positive?
    self > 0
  end

  def negative?
    self < 0
  end

  def -@
    0 - self
  end

  def +@
    self
  end

  def succ
    self + 1
  end

  def next
    self + 1
  end

  def pred
    self - 1
  end

  def abs
    self < 0 ? -self : self
  end
end

class Integer
  def <=>(other)
    return nil unless other.is_a?(Integer)

    self < other ? -1 : (self > other ? 1 : 0)
  end

  def between?(low, high)
    self >= low && self <= high
  end

  def clamp(low, high)
    self < low ? low : (self > high ? high : self)
  end
end

class Integer
  def eql?(other) = other.is_a?(Integer) && self == other
  def hash = self
end
