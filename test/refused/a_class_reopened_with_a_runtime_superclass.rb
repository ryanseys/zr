# a class reopened with a runtime superclass
base = Object

class Foo
  def one = 1
end

class Foo < base
  def two = 2
end
