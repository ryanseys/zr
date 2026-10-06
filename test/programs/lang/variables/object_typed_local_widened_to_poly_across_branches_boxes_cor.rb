# `x`'s two branches assign DIFFERENT classes, so the local must widen
# to a common type across the branches, and each branch's own object
# must still work correctly through it afterward.

class Foo
  def initialize
    @tag = "foo"
  end
  def tag
    @tag
  end
end

class Bar
  def initialize
    @tag = "bar"
  end
  def tag
    @tag
  end
end

class Picker
  def pick(flag)
    if flag
      x = Foo.new
    else
      x = Bar.new
    end
    x
  end
end

p = Picker.new
puts p.pick(true).tag
puts p.pick(false).tag
