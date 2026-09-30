# frozen_string_literal: true

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

