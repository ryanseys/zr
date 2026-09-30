def each_twice
  yield 1
  yield 2
  :done
end

def maybe
  return :no_block unless block_given?

  yield 41
end

def collect
  out = []
  yield out
  out
end

p [1, 2, 3].each { |x| puts x }
p [1, 2, 3].map { |x| x * 2 }
p [1, 2, 3, 4].select { |x| x > 2 }
p({ "a" => 1, "b" => 2 }.map { |k, v| "#{k}=#{v}" })
p [[1, 2], [3, 4]].map { |a, b| a + b }
p [3, 1, 2].sort { |a, b| a <=> b }

p(each_twice { |x| puts x })
p maybe
p(maybe { |x| x + 1 })
p(collect { |o| o << :one; o << :two })
p(each_twice { |x| break :broken })

p [1, 2, 3].each { |x| next if x == 2; puts x }
p [1, 2, 3].map { |x| next 0 if x == 2; x }
p [1, 2, 3].each { |x| break :stopped if x == 2 }

offset = 10
p [1, 2].map { |x| x + offset }

total = 0
[1, 2, 3].each { |x| total += x }
p total

label = "n"
p [1, 2].map { |i| "#{label}#{i}" }

pairs = []
[1, 2].each { |i| [10, 20].each { |j| pairs << i * j } }
p pairs

made = []
[1, 2, 3].each { |i| made << proc { i * 100 } }
p made.map { |pr| pr.call }

pr = proc { |x, y| x }
p pr.call(7, 8)
p pr.arity
p pr.lambda?
p pr.parameters
la = lambda { |x, y| x - y }
p la.call(10, 3)
p la.arity
p la.lambda?

# A `yield` written INSIDE a block reaches the enclosing method's block,
# which the proc carries along. Two of them in sibling branches read one
# value, and neither branch runs before the other.
def relay(list)
  list.map do |n|
    if n.odd?
      yield n
    else
      yield(n * 10)
    end
  end
end

p relay([1, 2, 3]) { |v| v + 100 }

# `block_given?` and a `->` in the same block read it too.
def either(list)
  list.map do |n|
    next (-> { n }).call unless block_given?

    yield n
  end
end

p either([1, 2])
p either([1, 2]) { |v| v * 3 }

def boom
  [1].each { |x| raise "inside" }
end
boom
