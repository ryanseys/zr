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

b = B.new
b.add("z")
p b.get

