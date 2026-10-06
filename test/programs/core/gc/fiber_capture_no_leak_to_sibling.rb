# A Fiber.new block body captures a local. A method defined
# later with a param of the same name (a top-level
# `def do_work(client)` called from inside the fiber body) has
# its own local, not the captured one.

def spawn_for(client)
  f = Fiber.new do
    do_work(client)
  end
  f
end

def do_work(client)
  puts "client=" + client.to_s
end

f = spawn_for(42)
f.resume
