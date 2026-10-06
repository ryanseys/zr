# A method that `alias m m` marked is an alias in ruby, and its
# redefinition does not warn, for a core method too; a core method with
# no alias warns, also after `private`.
$VERBOSE = true
class ::BasicObject
  alias_method :initialize, :initialize
  def initialize
    @bug = "[Bug #21992]"
  end
end
p Object.new.instance_variable_get(:@bug)
class String
  alias size size
  def size = 1
end
p "abc".size
class Array
  def length = 0
end
class Hash
  private :size
  def size = 2
end
class Foo
  def bar = 1
  alias bar bar
  def bar = 2
end
p Foo.new.bar
