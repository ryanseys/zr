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

# the desugared and mutating spellings already worked; keep them pinned
class T
  def initialize
    @a = []
    nil
  end

  def plus(x)
    @a += [x]
    nil
  end

  def shovel(x)
    @a << x
    nil
  end

  def get
    @a
  end
end

t = T.new
t.plus("p")
t.shovel("s")
p t.get

