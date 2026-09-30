# Default arguments at call sites, and the scope of a default
# expression. Each section covers a distinct dispatch path. The
# class names are specific to each path (SelfDefault / CalleeFoo).

# ---- Implicit-self call inside same class ----
# Bare-method dispatch from within a class body must also fill in
# the callee's defaults.
class SelfDefault
  def initialize
    bar
    bar(99)
  end
  def bar(x = 42)
    puts x
  end
end
SelfDefault.new
# 42
# 99

