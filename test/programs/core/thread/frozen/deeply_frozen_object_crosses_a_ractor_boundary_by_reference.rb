class Box
  def initialize(v)
    @v = v
  end
  def v
    @v
  end
end
b = Box.new(41)
Ractor.make_shareable(b)
puts b.frozen?
sink = Ractor.new do
  got = Ractor.receive
  got.send(:v)
end
sink.send(b)
puts sink.value + 1
