# Fiber#transfer back to the root fiber (Fiber.current obtained in main).
# The root fiber already runs, so a transfer to it resumes it where it
# stopped. It does not start again from the beginning.

main = Fiber.current

f = Fiber.new do
  puts "in fiber"
  v = main.transfer(42)
  puts "fiber resumed with #{v.inspect}"
  main.transfer(99)
  puts "never reached"
end

r = f.transfer
puts "back in main: #{r.inspect}"
r2 = f.transfer(7)            # resume f where it suspended
puts "back in main again: #{r2.inspect}"

# Several round trips through root, value passed each way (while loop,
# no nested block in the fiber body).
g = Fiber.new do
  acc = 0
  n = 0
  while n < 3
    got = main.transfer(acc)
    acc += got
    n += 1
  end
  main.transfer(acc)
end

p g.transfer        # 0
p g.transfer(10)    # acc=10 -> yields 10
p g.transfer(5)     # acc=15 -> yields 15
p g.transfer(100)   # acc=115
