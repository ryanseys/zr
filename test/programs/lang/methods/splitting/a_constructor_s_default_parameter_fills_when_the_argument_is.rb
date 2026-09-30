# Default arguments at call sites, and the scope of a default
# expression. Each section covers a distinct dispatch path. The
# class names are specific to each path (SelfDefault / CalleeFoo).

# ---- Constructor default ----
# `Counter.new` (no arg) and `Counter.new(7)` both need to compile.
class Counter
  def initialize(start = 0)
    @n = start
  end
  attr_reader :n
end
puts Counter.new.n         # 0
puts Counter.new(7).n      # 7

