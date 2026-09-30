# each_with_index on an array whose type is known only at run time (a def
# parameter, or an element of a nested array). It binds the whole element and
# the loop index, and never splats a nested-array element (unlike `each`).
def show(cells)
  cells.each_with_index do |v, i|
    puts "#{i}:#{v}"
  end
end
show(["x", 1, :sym])

def rows(data)
  data.each do |row|
    row.each_with_index { |c, i| puts "#{i}=#{c}" }
  end
end
rows([["a", "b"], ["c", "d"]])

def total(xs)
  sum = 0
  xs.each_with_index { |_v, i| sum += i }
  sum
end
puts total([10, 20, 30, 40])

# `cond ? array : hash` gives a value that can be an Array or a Hash. The cases
# below check how the block params bind.
def poly(cond)
  cond ? [10, 20, 30] : { a: 1 }
end

# UNUSED index param: the block never reads `i`.
poly(true).each_with_index { |v, i| puts v }

# EXTRA param beyond the yielded (element, index) arity binds to nil each
# iteration -- a reassigned extra must not leak its prior value across passes.
poly(true).each_with_index { |v, i, x| x = 99 unless x.nil?; puts "#{v}/#{i}/#{x.inspect}" }
