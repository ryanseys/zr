# A flip-flop's state is a special variable of the frame, which each
# thread has apart. zr keeps one state for the Proc, which both threads
# change.
ff = proc { |n| true if n == 3..n == 5 }
v = 1..9
a = true
th = Thread.new do
  v.select do |i|
    Thread.pass while a
    ff[i].tap { a = true }
  end
end
v1 = v.select do |i|
  Thread.pass until a
  ff[i].tap { a = false }
end
p v1, th.value
