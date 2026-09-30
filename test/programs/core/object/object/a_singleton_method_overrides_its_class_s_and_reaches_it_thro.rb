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

# override a parent method + super
class Widget
  def initialize(n)
    @n = n
  end
  def label
    "widget-#{@n}"
  end
end
W1 = Widget.new(1)
def W1.label
  "custom-#{super}"
end
def W1.tag
  @tag = "T"
  @tag
end
p W1.label
p W1.tag
# poly dispatch alongside a plain instance
[W1, Widget.new(2)].each { |w| puts w.label }

