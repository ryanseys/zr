# Bare `attr_reader_name` and `self.attr_reader_name` inside a
# subclass instance method call the reader that the parent class
# declares with `attr_accessor` / `attr_reader`.

class T_subclass_inherited_attr_reader_Base
  attr_accessor :fmt
  attr_reader :tag
  def initialize
    @fmt = :html
    @tag = :base_tag
  end
end

class T_subclass_inherited_attr_reader_Sub < T_subclass_inherited_attr_reader_Base
  def doit
    fmt == :html ? "html" : "json"
  end
  def doit_self
    self.fmt == :html ? "html-self" : "json-self"
  end
  def tag_str
    tag.to_s
  end
end

s = T_subclass_inherited_attr_reader_Sub.new
puts s.doit
puts s.doit_self
puts s.tag_str

# Deeper chain: grandchild via T_subclass_inherited_attr_reader_Mid -> T_subclass_inherited_attr_reader_Base.
class T_subclass_inherited_attr_reader_Mid < T_subclass_inherited_attr_reader_Base
end

class T_subclass_inherited_attr_reader_Leaf < T_subclass_inherited_attr_reader_Mid
  def show
    fmt.to_s + "/" + tag.to_s
  end
end

puts T_subclass_inherited_attr_reader_Leaf.new.show
