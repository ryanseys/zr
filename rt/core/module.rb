# Module's comparisons over the ancestor chain, and the hooks a program
# may override, which do nothing here.
class Module
  private def included(base) = nil
  private def extended(base) = nil
  private def prepended(base) = nil
  private def method_added(name) = nil

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

class Class
  private def inherited(subclass) = nil
end
