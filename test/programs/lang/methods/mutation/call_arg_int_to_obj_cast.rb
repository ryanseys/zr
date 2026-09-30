# A method can return an object of one of two classes. A local
# holds the result, and the program passes that local as an
# argument to a method that expects one of the classes.

class Holder
  attr_reader :name
  def initialize(name)
    @name = name
  end
end

class Wrapper
  attr_reader :tag
  def initialize(tag)
    @tag = tag
  end
end

# The helper returns a Holder or a Wrapper:
def maybe_holder(flag)
  if flag == 0
    Holder.new("h0")
  else
    Wrapper.new("w0")
  end
end

def consume_holder(h)
  h.name
end

# Push instances into a heterogeneous array so neither class
# stays value-typed.
all = [Holder.new("init"), Wrapper.new("init")]

h = maybe_holder(0)
all << h

# `h` holds a Holder, so consume_holder answers its name.
puts consume_holder(h)
