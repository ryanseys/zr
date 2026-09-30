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

# define_singleton_method
class Box
  def v
    1
  end
end
B = Box.new
B.define_singleton_method(:doubled) { v * 2 }
p B.doubled

