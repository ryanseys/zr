# Module's comparisons over the ancestor chain.
class Module
  def <(other)
    raise TypeError, "compared with non class/module" unless other.is_a?(Module)
    return false if equal?(other)
    return true if include?(other) || ancestors.include?(other)

    other.ancestors.include?(self) ? false : nil
  end

  def <=(other)
    equal?(other) ? true : self < other
  end

  def >(other)
    raise TypeError, "compared with non class/module" unless other.is_a?(Module)
    return false if equal?(other)

    r = other < self
    r.nil? ? nil : r
  end

  def >=(other)
    equal?(other) ? true : self > other
  end

  def <=>(other)
    return 0 if equal?(other)
    return nil unless other.is_a?(Module)

    r = self < other
    return -1 if r
    return 1 if r == false && other < self

    nil
  end
end
