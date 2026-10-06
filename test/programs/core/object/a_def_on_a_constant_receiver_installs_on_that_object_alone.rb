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

p CONFIG.base
p CONFIG.reload
p CONFIG.scale(3)
p CONFIG.class
p CONFIG.class.name
p CONFIG.is_a?(Config)
p CONFIG.instance_of?(Config)

