sq = ->(x) { x * x }
p sq.call(3), sq.(4), sq[5], sq.lambda?, proc {}.lambda?
add = lambda { |a, b| a + b }
p add.call(1, 2)
begin
  add.call(1)
rescue ArgumentError => e
  puts e.message
  puts e.backtrace
end
two = ->(a, b) { [a, b] }
begin
  two.call([1, 2])
rescue ArgumentError => e
  puts e.message
end
pr = proc { |a, b| [a, b] }
p pr.call([1, 2]), pr.call(1), pr.call(1, 2, 3)
def ret_test
  l = -> { return :from_lambda }
  v = l.call
  [v, :after]
end
p ret_test
def ret_proc
  pr = proc { return :from_proc }
  pr.call
  :not_reached
end
p ret_proc
def brk
  l = -> { break :broke }
  [l.call, :after_break]
end
p brk
nx = ->(x) { next x * 2 }
p nx.call(4)
def outer_proc
  proc { break :b }
end
begin
  outer_proc.call
rescue LocalJumpError => e
  puts e.message
end
begin
  Proc.new
rescue ArgumentError => e
  puts e.message
end
p Proc.new { |x| x }.call(9)
def yielder(&b) = b
b = yielder { |x| x + 1 }
p b.call(1), b.lambda?
m = ->(x, y = 1, *r, k: 2) { [x, y, r, k] }
p m.call(1), m.(1, 2, 3, k: 4)
p((->() { :zero }).call)
p [1, 2, 3].map(&sq)
counter = 0
inc = -> { counter += 1 }
inc.call
inc.()
p counter
