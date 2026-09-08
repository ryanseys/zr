# frozen_string_literal: true

# `for` performs NO type dispatch -- ruby compiles it to `coll.each { |x|
# ... }` -- and it opens NO scope: the index is a name of the body
# around it and outlives the loop. `redo` runs the body again without
# stepping, and a block-local is a name the block alone can see.

for i in 1..3
  print i
end
puts
p i

for a, b in [[1, 2], [3, 4]]
  p [a, b]
end
p [a, b]

pairs = []
for key, value in { one: 1, two: 2 }
  pairs << [key, value]
end
p pairs, key, value

# A single index over a multi-value yield binds the WHOLE pair.
for pair in { three: 3 }
  p pair
end

# The Array is live: what the body appends is walked.
grown = [1]
for g in grown
  grown << 2 if g == 1
  print g
end
puts

out = []
for x in [1, 2, 3, 4]
  next if x == 2
  break if x == 4

  out << x
end
p out, x

# Running out answers the collection; a `break` supplies its own.
p(for c in [1, 2] do end)
p(for d in (1...4) do print d end)
puts
p(for e in [1, 2, 3] do break e * 10 if e == 2 end)

for outer in [1, 2]
  for inner in %i[x y]
    print "#{outer}#{inner} "
  end
end
puts

# A raise inside the body leaves the loop's own state behind cleanly.
begin
  for r in [1, 2]
    raise ArgumentError, "stop" if r == 2
  end
rescue ArgumentError => err
  p err.message, r
end

begin
  for n in 5
    p n
  end
rescue NoMethodError => err
  p err.message
end

def first_over(list, limit)
  for item in list
    return item if item > limit
  end
  :none
end

p first_over([1, 2, 3], 1), first_over([1], 9)

# An `ensure` the jump crosses runs its clause and the jump goes on.
def guarded(list)
  log = []
  for n in list
    begin
      next if n == 2
      break if n == 4

      log << n
    ensure
      log << [:e, n]
    end
  end
  log
end

p guarded([1, 2, 3, 4, 5])

# `redo` in a native loop steps nothing.
turns = 0
count = 0
while count < 2
  count += 1
  turns += 1
  redo if turns == 1
end
p [count, turns]

for z in [1, 2]
  turns += 1
  redo if turns == 3
end
p [z, turns]

# `redo` in a block re-enters PAST the bindings, so the parameter keeps
# what the body assigned to it.
steps = []
[10].each do |v|
  steps << v
  if v < 12
    v += 1
    redo
  end
end
p steps

# ...and an `ensure` in the way runs each time round.
log = []
attempts = 0
[1].each do |_|
  begin
    attempts += 1
    redo if attempts < 3
  ensure
    log << attempts
  end
end
p log

# A block-local starts nil every invocation and never touches the name
# outside it.
scratch = :outer
seen = []
[1, 2].each do |n; scratch|
  seen << scratch
  scratch = n
  seen << scratch
end
p seen, scratch

# It survives a redo, exactly as a parameter does.
kept = []
rounds = 0
[1].each do |_; held|
  held = (held || 0) + 1
  kept << held
  rounds += 1
  redo if rounds < 3
end
p kept
__END__
123
3
[1, 2]
[3, 4]
[3, 4]
[[:one, 1], [:two, 2]]
:two
2
[:three, 3]
12
[1, 3]
4
[1, 2]
1231...4

20
1x 1y 2x 2y 
"stop"
2
"undefined method 'each' for an instance of Integer"
2
:none
[1, [:e, 1], [:e, 2], 3, [:e, 3], [:e, 4]]
[2, 2]
[2, 5]
[10, 11, 12]
[1, 2, 3]
[nil, 1, nil, 2]
:outer
[1, 2, 3]
