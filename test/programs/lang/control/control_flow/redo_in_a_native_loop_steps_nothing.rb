# frozen_string_literal: true

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

