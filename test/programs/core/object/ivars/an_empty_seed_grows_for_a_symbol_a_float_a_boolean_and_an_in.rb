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

class S
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

[:z, 1.5, true, 1].each do |v|
  s = S.new
  s.add(v)
  p s.get
end

