class B
  def initialize
    @a = []
    nil
  end

  def add(x)
    @a = @a + [x]
    nil
  end

  def get
    @a
  end
end

m = B.new
m.add("x")
m.add("y")
m.add("z")
p m.get
p m.get.length
p m.get.join(",")

