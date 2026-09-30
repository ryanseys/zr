# A `return` written in a block that sits inside a lambda leaves the
# lambda, not the method that made the lambda: a lambda is the innermost
# frame a return can name.
def first(items)
  f = ->(list) {
    list.each do |x|
      return x if x > 1
    end
    :fell_through
  }
  [f.call(items), :after]
end

p first([1, 2, 3])
p first([0, 1])

# Two blocks deep inside the lambda.
def deep
  g = ->(rows) {
    rows.each do |row|
      row.each do |cell|
        return cell if cell == :found
      end
    end
    :none
  }
  [g.call([[:a], [:found, :b]]), g.call([[:a]])]
end

p deep

# A plain block inside a method still returns from the method.
def plain
  [1, 2].each { |x| return x }
  :not_here
end

p plain

# The lambda ended, so its frame answers no return any more.
def escaped
  ->(_) { proc { return :late } }.call(nil)
end

held = escaped
begin
  held.call
rescue LocalJumpError => e
  p [e.class, e.message]
end

# An ensure on the way out of the lambda runs.
def with_ensure
  h = -> {
    [1].each do
      begin
        return :body
      ensure
        puts "ensure ran"
      end
    end
  }
  h.call
end

p with_ensure

# A lambda inside a lambda: the innermost one takes the return.
outer = ->(n) {
  inner = ->(m) {
    [m].each { |x| return x * 2 }
    :inner_fell
  }
  [inner.call(n), :outer_went_on]
}
p outer.call(5)

