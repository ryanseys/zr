# Default arguments at call sites, and the scope of a default
# expression. Each section covers a distinct dispatch path. The
# class names are specific to each path (SelfDefault / CalleeFoo).

# ---- Default expression reads @ivar ----
# The default expression runs against the call's *receiver* (here
# the receiver `@w` of Wrapper#grab), not the caller's `self`.
# WrapperCaller has no @base.
class Wrapper
  def initialize(seed)
    @base = seed
  end
  def grab(target = @base * 10)
    target
  end
end
class WrapperCaller
  def initialize
    @w = Wrapper.new(3)
  end
  def go
    @w.grab
  end
end
puts WrapperCaller.new.go        # 30

