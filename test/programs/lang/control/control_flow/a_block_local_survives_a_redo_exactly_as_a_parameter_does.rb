# frozen_string_literal: true

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
