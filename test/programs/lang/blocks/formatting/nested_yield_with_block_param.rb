# `outer { |x| yield x*2 }` inside a method that itself yields (`inner`):
# the inner `yield` goes to the block of the caller of `inner`.

def outer
  yield 1
end

def inner
  outer do |x|
    yield x * 2
  end
end

inner { |v| puts v.to_s }

# Multi-arg yield path. inner forwards a 2-tuple, outer's block param
# captures and re-yields one of them. Exercises both args + offsets.
def add_one
  yield 10
end

def double_then_emit
  add_one do |n|
    yield n + 5
  end
end

double_then_emit { |r| puts r.to_s }
