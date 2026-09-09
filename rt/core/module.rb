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
    return true if ancestors.include?(other)

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

class BasicObject
  private def singleton_method_added(name) = nil
end

module Kernel
  private def initialize_copy(orig)
    raise TypeError, "initialize_copy should take same class object" unless orig.instance_of?(self.class)

    self
  end

  private def initialize_dup(orig) = initialize_copy(orig)
  private def initialize_clone(orig, freeze: nil) = initialize_copy(orig)
end
