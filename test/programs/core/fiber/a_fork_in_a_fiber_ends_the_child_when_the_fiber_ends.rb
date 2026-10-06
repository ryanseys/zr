# In the child of a fork inside a fiber, that fiber is the root: when it
# ends, the child ends as a program does, with its at_exit handlers.
at_exit { puts "at_exit in #{Process.pid == $parent ? "parent" : "child"}" }
$parent = Process.pid
r = Fiber.new do
  fork
ensure
  puts "ensure in fiber"
end.resume
if r
  Process.wait(r)
  p [:parent, $?.exitstatus]
else
  puts "child continues"
end

# A fiber that raises after the fork ends the child with status 1.
r = Fiber.new do
  pid = fork
  raise "boom in child" unless pid
  pid
end.resume
if r
  Process.wait(r)
  p [:parent2, $?.exitstatus]
end

# A fiber that exits with a status.
r = Fiber.new do
  pid = fork
  exit 7 unless pid
  pid
end.resume
Process.wait(r)
p [:parent3, $?.exitstatus]

# A fiber made in the child after the fork comes back to it.
r = Fiber.new do
  pid = fork
  unless pid
    inner = Fiber.new { Fiber.yield :inner; :done }
    puts [inner.resume, inner.resume].inspect
    other = Fiber.new { :transferred }
    puts other.transfer.inspect
  end
  pid
end.resume
Process.wait(r)
p [:parent4, $?.exitstatus]
