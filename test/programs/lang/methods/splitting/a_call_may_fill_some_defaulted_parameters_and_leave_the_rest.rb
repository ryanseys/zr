# Default arguments at call sites, and the scope of a default
# expression. Each section covers a distinct dispatch path. The
# class names are specific to each path (SelfDefault / CalleeFoo).

# ---- Partial defaulting ----
# Caller supplies some leading positional args; trailing defaults
# fill the rest.
class M
  def f(a, b = 1, c = 2)
    puts a + b + c
  end
end
m = M.new
m.f(10)             # 13
m.f(10, 20)         # 32
m.f(10, 20, 30)     # 60

