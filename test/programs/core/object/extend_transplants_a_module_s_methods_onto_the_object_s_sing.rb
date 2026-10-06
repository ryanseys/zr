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

# obj.extend(Mod): transplant module methods onto the singleton subclass
module Loud
  def shout
    label.upcase
  end
end
module Soft
  def whisper
    label.downcase
  end
end
class Speaker
  def initialize(s)
    @s = s
  end
  def label
    @s
  end
end
SPK = Speaker.new("Hi")
SPK.extend(Loud)
SPK.extend(Soft)
def SPK.both
  "#{shout}/#{whisper}"
end
p SPK.shout
p SPK.whisper
p SPK.both
p SPK.class
