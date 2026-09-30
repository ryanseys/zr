# `self[k]` and `self[k] = v` from inside a parent-defined method
# call the subclass override at runtime, not the parent's operator.
# This is the operator form of a bare method call to a subclass.
#
# Roundhouse example: ActiveRecord::Base#fill_timestamps does
# `self[:updated_at] = now if cols.include?(:updated_at)`, and
# the call goes to the column code of the subclass. No model
# raises NotImplementedError.

class Base
  def [](name)
    raise NotImplementedError
  end

  def []=(name, value)
    raise NotImplementedError
  end

  def fetch
    self[:foo]
  end

  def fill
    self[:foo] = "bar"
  end
end

class Article < Base
  def [](name); "result"; end
  def []=(name, value); @foo = value; end
  def foo; @foo; end
end

a = Article.new
puts a.fetch
a.fill
puts a.foo
