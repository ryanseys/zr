# A subclass inherits a class method whose body calls another class
# method (`self.last` calls bare `all`). The bare `all` calls the
# subclass's override, so `records` holds the subclass's Array of
# objects, not the parent's empty Array.

class T_inherited_cmethod_subclass_dispatch_Base
  def self.all
    []
  end

  def self.last
    records = all
    records.empty? ? nil : records[-1]
  end
end

class T_inherited_cmethod_subclass_dispatch_Sub < T_inherited_cmethod_subclass_dispatch_Base
  def self.all
    [Object.new]
  end
end

# T_inherited_cmethod_subclass_dispatch_Sub.last (inherited from T_inherited_cmethod_subclass_dispatch_Base)
# gets T_inherited_cmethod_subclass_dispatch_Sub.all's Array, so `records[-1]` is the object.
r = T_inherited_cmethod_subclass_dispatch_Sub.last
if r != nil
  puts "got object"
else
  puts "nil"
end
