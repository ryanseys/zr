# A user-defined `sample` returns its own value (a String here), not
# an element as Array#sample does.

class T_sample_user_method_Box
  def initialize(label)
    @label = label
  end

  attr_reader :label

  def sample
    @label
  end
end

b = T_sample_user_method_Box.new("ok")
puts b.sample    # ok
