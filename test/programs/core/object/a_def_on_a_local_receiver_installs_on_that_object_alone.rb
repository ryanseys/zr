# Singleton methods on a constant/local that statically holds one object:
# synthesized as an anonymous subclass that masquerades as its parent.
class Config
  def initialize
    @base = 10
  end
  def base
    @base
  end
end

CONFIG = Config.new
def CONFIG.reload
  "reloaded-#{base}"
end
def CONFIG.scale(n)
  base * n
end

# local receiver
class Thing
  def base
    "b"
  end
end
x = Thing.new
def x.special
  "s-#{base}"
end
p x.special
p x.class

