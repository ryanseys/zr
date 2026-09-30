# Default arguments at call sites, and the scope of a default
# expression. Each section covers a distinct dispatch path. The
# class names are specific to each path (SelfDefault / CalleeFoo).

# ---- Default expression calls a same-class bare method ----
# CallerBar defines its own `target` returning 2, but CalleeFoo's
# default-arg `target` must still dispatch to CalleeFoo#target
# (returning 1) rather than the caller's `target`.
class CalleeFoo
  def target
    1
  end
  def foo(opt = target)
    opt
  end
end
class CallerBar
  def target
    2     # different value — must NOT be picked up by CalleeFoo#foo
  end
  def check
    CalleeFoo.new.foo
  end
end
puts CallerBar.new.check         # 1
