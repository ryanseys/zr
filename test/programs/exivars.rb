s = +"str"
s.instance_variable_set(:@tag, 1)
p s.instance_variable_get(:@tag), s.instance_variables, s
a = [1]
a.instance_variable_set(:@n, :x)
p a.instance_variable_get(:@n), a.instance_variables, [2].instance_variables
class Tagged < StandardError
  def initialize(code)
    @code = code
    super("code #{code}")
  end
  attr_reader :code
end
begin
  raise Tagged, 7
rescue Tagged => e
  p e.code, e.message, e.instance_variables
end
class String
  def mark! = @marked = true
  def marked? = @marked == true
end
t = +"abc"
p t.marked?
t.mark!
p t.marked?, "abc".marked?
h = { a: 1 }
h.instance_variable_set(:@h, 2)
p h.instance_variable_get(:@h)
pr = proc { }
pr.instance_variable_set(:@p, 3)
p pr.instance_variable_get(:@p)
begin
  1.instance_variable_set(:@x, 1)
rescue FrozenError => e
  p e
end
begin
  :sym.instance_variable_set(:@x, 1)
rescue FrozenError => e
  p e
end
begin
  nil.instance_variable_set(:@x, 1)
rescue FrozenError => e
  p e
end
p 1.instance_variable_get(:@x), nil.instance_variables
i = 0
while i < 2000
  x = [i]
  x.instance_variable_set(:@i, "s#{i}")
  i += 1
end
p x.instance_variable_get(:@i)
