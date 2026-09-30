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

# computed inside the class, which was correct before too
class U
  def initialize
    @a = []
    nil
  end

  def add(x)
    @a = @a + [x]
    nil
  end

  def joined
    @a.join(",")
  end

  def sorted
    @a.sort.join(",")
  end
end

u = U.new
u.add("b")
u.add("a")
p u.joined
p u.sorted
