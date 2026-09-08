# frozen_string_literal: true

# `alias` names a method wherever it is written -- the definee is `self`
# where `self` is a class or a module, and the enclosing class
# otherwise, which at the top level is `Object`.

def hello = "hi"
alias howdy hello
p howdy

class C
  def a = 1
end

# A reopen names the same class, so the alias lands where `a` is.
class C
  alias b a
end
p C.new.b

# `alias $new $old` names the STORAGE, so a write through either name is
# visible through both.
$first = 1
alias $second $first
$second = 2
p $first

# These verbs take a name, and ruby lets it be written as a String.
class Named
  attr_reader "x"
  attr_writer "y"
  attr_accessor "z"
  alias_method "w", "x"

  def initialize
    @x = 1
    @y = 2
    @z = 3
  end

  def hidden = :h
  private "hidden"

  # One the declaration pass cannot reach -- written inside another
  # expression -- is an ordinary send of `Module#attr_reader`.
  p(attr_reader(:late))
end

n = Named.new
p n.x, n.w
n.z = 8
p n.z
p Named.instance_methods(false).sort
p Named.private_instance_methods(false).sort
__END__
"hi"
1
2
[:late]
1
1
8
[:late, :w, :x, :y=, :z, :z=]
[:hidden, :initialize]
