class C
  def inspect
    @memo ||= "a C"
  end
end
c = C.new.freeze
begin
  c.instance_variable_set(:@x, 1)
rescue => e
  p e.class, e.message, e.receiver.equal?(c)
end
begin
  c.instance_variable_set(:@y, 2)
rescue => e
  p e.message
end
