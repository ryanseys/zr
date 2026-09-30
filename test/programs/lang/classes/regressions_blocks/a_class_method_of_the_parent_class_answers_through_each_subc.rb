# A class method (`def self.<name>`) that the parent class defines
# answers when a subclass calls it, at one level or at two.

class T_issue208_inherited_class_method_Base
  def self.all
    [42, 1, 7]
  end
end

# Single level
class T_issue208_inherited_class_method_Leaf < T_issue208_inherited_class_method_Base; end
puts T_issue208_inherited_class_method_Leaf.all.size                   # 3

# Multi level
class T_issue208_inherited_class_method_Mid < T_issue208_inherited_class_method_Base; end
class T_issue208_inherited_class_method_Deep < T_issue208_inherited_class_method_Mid; end
puts T_issue208_inherited_class_method_Mid.all.size                    # 3
puts T_issue208_inherited_class_method_Deep.all.size                   # 3

# Direct call on the defining class still works
puts T_issue208_inherited_class_method_Base.all.size                   # 3
