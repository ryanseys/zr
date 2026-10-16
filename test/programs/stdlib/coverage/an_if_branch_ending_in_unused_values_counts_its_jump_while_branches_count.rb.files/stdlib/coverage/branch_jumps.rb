def a(x)
  if x
    1
  else
    2
  end
  3
end
def b(x)
  unless x
    1
  end
  3
end
def c(x)
  case x
  when 1
    :one
  when 2
    :two
  end
  3
end
def d(x)
  if x
    1
  elsif x.nil?
    2
  end
  3
end
def e(x)
  x ? 1 : 2
  3
end
2.times { a(true); b(false); c(1); d(true); e(true) }
a(false); c(2); d(nil)
def g(x)
  if x
    y = 1
    :void
  else
    2
  end
end
3.times { g(true) }
g(false)
