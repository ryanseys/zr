class Greeter
  def hello
    "hi"
  end
  alias hola hello
end
g = Greeter.new
puts g.hello
puts g.hola
