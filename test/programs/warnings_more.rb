# Warning as a module a program can turn off, redirect, or catch, and
# the constants a module says are on their way out.
p Warning.categories, Warning[:deprecated], Warning[:experimental]
begin
  Warning[:nope]
rescue ArgumentError => e
  puts e.message
end

module Old
  GONE = 1
  KEPT = 2
  deprecate_constant :GONE
end
Old::GONE
Warning[:deprecated] = true
Old::GONE
p Old::KEPT
Warning[:deprecated] = false

def inner
  warn "from inner", uplevel: 0
  warn "from the caller", uplevel: 1
  warn "past the top", uplevel: 9
end
def outer = inner
outer
warn "first", "second", uplevel: 0
warn "no position"
warn
warn "quiet", category: :deprecated

module Warning
  def warn(message, category: nil)
    print "caught #{category.inspect}: #{message}"
  end
end
warn "through the override"
warn "a category", category: :experimental
