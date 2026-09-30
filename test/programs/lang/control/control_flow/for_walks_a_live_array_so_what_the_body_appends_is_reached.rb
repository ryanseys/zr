# frozen_string_literal: true

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

