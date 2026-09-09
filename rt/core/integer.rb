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
