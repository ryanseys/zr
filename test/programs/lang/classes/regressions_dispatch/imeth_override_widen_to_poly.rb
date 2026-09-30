# An override's `value` param gets values of mixed classes from its
# call sites. A `self[k] = v` inside a parent method calls the
# override, not the parent's method that raises.

class T_imeth_override_widen_to_poly_Base
  def []=(name, value); raise NotImplementedError; end
  def fill; self[:title] = "Hello"; end
end

class T_imeth_override_widen_to_poly_Article < T_imeth_override_widen_to_poly_Base
  attr_accessor :id, :title
  def []=(name, value)
    case name
    when :id then @id = value
    when :title then @title = value
    end
  end
end

a = T_imeth_override_widen_to_poly_Article.new
a.id = 0
a.title = ""
a[:id] = 42
a[:title] = "Other"
a.fill
puts a.title.inspect
