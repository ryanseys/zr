# `$~` lives in the scope of the method that a block is written in. A
# Proc of the block sees the match of its last call after the method
# returned, and on another stack (a Thread's or a Fiber's), as the
# method's other blocks do.
def scope
  pr = proc do |s|
    s =~ /(.)(.)?/ if s
    $~ && $~[0]
  end
  Thread.new do
    pr.("x")
    p pr.(nil)
  end.join
  pr
end
later = scope
later.("z")
p later.(nil)
p $~

def groups
  setter = ->(s) { s =~ /(\w)(\d)/ }
  reader = -> { [$1, $2, Regexp.last_match&.pre_match] }
  [setter, reader]
end
setter, reader = groups
setter.("ab3")
p reader.()

def nested
  outer = proc do
    inner = proc { |s| s =~ /n(.)/ if s; $1 }
    inner
  end
  outer.call
end
inner = nested
inner.("no")
p inner.(nil)

def in_fiber
  pr = proc { |s| s =~ /f(.)/ if s; $~&.[](1) }
  Fiber.new { pr.("fz") }.resume
  [pr.(nil), $~&.[](0)]
end
p in_fiber

# Each call of the method has its own `$~`.
first = scope
second = scope
first.("a")
p second.(nil), first.(nil)
