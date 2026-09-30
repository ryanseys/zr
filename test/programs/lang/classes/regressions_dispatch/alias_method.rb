# AliasMethodNode -- `alias greet hello` inside a class body.
#
# CRuby snapshots the method at alias time -- if `hello` is later
# redefined, `greet` still calls the original. Here a call to
# `.greet` runs the body of `.hello`. This test does not check alias
# inside a method body, or alias of an inherited method.

class T_alias_method_Greeter
  def hello = "hi from hello"
  alias greet hello
end

g = T_alias_method_Greeter.new
puts g.hello   # hi from hello
puts g.greet   # hi from hello

# Two aliases of the same method.
class T_alias_method_Counter
  def value = 42
  alias get value
  alias read value
end
c = T_alias_method_Counter.new
puts c.value   # 42
puts c.get     # 42
puts c.read    # 42
