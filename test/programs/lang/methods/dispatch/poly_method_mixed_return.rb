# Poly dispatch where user classes disagree on the method's return
# type. `Foo#name` returns int, `Bar#name` returns string. The result
# of `a.name` is genuinely polymorphic — each call gives the value of
# the method that ran.

class Foo
  def name
    42
  end
end

class Bar
  def name
    "bar"
  end
end

def show(a)
  a.name
end

puts show(Foo.new)
puts show(Bar.new)
