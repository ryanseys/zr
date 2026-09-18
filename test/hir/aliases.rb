class K
  def greet = "hi"
  alias :"say_#{1}" :greet
  def farewell = "bye"
  def part = "part"
  undef :"farewell", :"#{"pa"}rt"
end
p K.new.say_1
p K.instance_methods(false).sort
name = "greet"
K.class_eval { alias_method :hello, name }
p K.new.hello
