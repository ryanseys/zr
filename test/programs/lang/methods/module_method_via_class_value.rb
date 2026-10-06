# `target.seen(x)` where `target` holds a Class value the analysis cannot pin to
# one class -- a parameter, an element, an untyped slot -- reaches every class
# method of that name at run time, so every one of them has this call as a
# caller. A caller that names the module outright does not settle the parameter
# type alone. The call through the variable gets
# each value with its real type: an object, a String or an Integer.
class Named
end

module Lang
  def self.seen(path)
    path
  end
end

def through(target, path)
  target.seen(path)
end

p through(Lang, Named.new).class
p Lang.seen("x.rb")
p through(Lang, 42)
p through(Lang, [1, 2])
p through(Lang, "direct")

# two modules answering the same name, reached through the same variable
module Other
  def self.seen(path)
    "other:#{path}"
  end
end
p through(Other, 7)
p Other.seen("s")

# a class value held in an array element
mods = [Lang, Other]
p mods[0].seen(3)
p mods[1].seen(4)
