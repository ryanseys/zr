# `self.class.<cmeth>` inside a parent-defined instance method calls
# the class method of the object's own class, so a subclass override
# runs.
#
# Coverage:
#   - Plain T_self_class_subclass_dispatch_Base/T_self_class_subclass_dispatch_Child override.
#   - Multi-level (T_self_class_subclass_dispatch_GrandChild overrides label).
#   - Subclass that doesn't override -- inherits via the default
#     (T_self_class_subclass_dispatch_Sibling has no .label, falls through to T_self_class_subclass_dispatch_Base).
#   - Direct T_self_class_subclass_dispatch_Base instance still routes to T_self_class_subclass_dispatch_Base.

class T_self_class_subclass_dispatch_Base
  def self.label
    "BASE"
  end

  def describe
    self.class.label
  end
end

class T_self_class_subclass_dispatch_Child < T_self_class_subclass_dispatch_Base
  def self.label
    "CHILD"
  end
end

class T_self_class_subclass_dispatch_GrandChild < T_self_class_subclass_dispatch_Child
  def self.label
    "GRANDCHILD"
  end
end

class T_self_class_subclass_dispatch_Sibling < T_self_class_subclass_dispatch_Base
end

puts T_self_class_subclass_dispatch_Base.new.describe
puts T_self_class_subclass_dispatch_Child.new.describe
puts T_self_class_subclass_dispatch_GrandChild.new.describe
puts T_self_class_subclass_dispatch_Sibling.new.describe
