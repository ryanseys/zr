# `method_added` reaching a class through `extend`, both standard spellings.
#
# The first is the ClassMethods idiom: a module's `included` hook does
# `base.extend(ClassMethods)`, and `ClassMethods` defines `method_added`.
# The extend is inside a method that runs at mixin time, so the hook
# takes effect only at the include. Each later `def` in the class
# must call it.
#
# Kept beside it: the INHERITED spelling. Two shapes of one feature belong
# in one file, so a change that fixes one and breaks the other cannot pass.
module Hook
  def self.included(base) = base.extend(ClassMethods)

  module ClassMethods
    def method_added(name)
      (@added ||= []) << name
    end

    def added = @added
  end
end

class Uses
  include Hook
  def a; end
  def b; end
end

p Uses.added

# The inherited spelling, so the two are side by side.
class Base
  def self.method_added(name) = ((@seen ||= []) << name)
  def self.seen = @seen
end

class Child < Base
  def one; end
end

p Child.seen
