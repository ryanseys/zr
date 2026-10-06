# The storage of the root fiber must survive GC. The root fiber is
# not a heap object, so the collector must mark its storage as a
# root, or the hash that `Fiber[:k] = v` allocates at top level
# goes away on the next cycle.

Fiber[:answer] = 42

# Each turn allocates an Array and three Strings, all
# GC-tracked, which drives the heap past the 256KB threshold
# well inside the loop.
i = 0
while i < 10000
  garbage = ["garbage_" + i.to_s, "more_" + i.to_s, "still_" + i.to_s]
  i = i + 1
end

# Unmarked, the hash holding :answer would be freed and this would
# read nil.
v = Fiber[:answer]
if v == 42
  puts "survived"
else
  puts "lost"
end
