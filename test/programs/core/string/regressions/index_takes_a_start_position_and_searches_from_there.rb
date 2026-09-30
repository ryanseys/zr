# `String#index(sub, start)` 2-arg form searches from `start`, so a
# "find next dot after position N" walk finds each dot in turn.
#
# `String#index` returns nil for not-found, as in CRuby.
# `puts nil.to_s` prints an empty line; the walk-all-dots loop
# checks `pos.nil?`.

s = "a.b.c.d"

# 1-arg form -- baseline.
puts s.index(".").to_s          # 1

# 2-arg form -- the fix.
puts s.index(".", 0).to_s       # 1   (no skip, finds the same first dot)
puts s.index(".", 1).to_s       # 1   (start at the dot itself, finds it)
puts s.index(".", 2).to_s       # 3   (skip past the first dot, find the second)
puts s.index(".", 4).to_s       # 5
puts s.index(".", 6).to_s       # "" (nil.to_s; CRuby would print blank)

# Negative start counts from end.
puts s.index(".", -1).to_s      # "" (not found, nil.to_s)
puts s.index(".", -2).to_s      # 5    (last dot)
puts s.index(".", -100).to_s    # 1    (clamps to 0)

# Out-of-range positive start.
puts s.index(".", 100).to_s     # "" (not found, nil.to_s)

# Multibyte: codepoint indexing, not byte indexing.
m = "α.β.γ"
puts m.index(".").to_s          # 1   (one cp before the first dot)
puts m.index(".", 2).to_s       # 3   (after the first dot)

# Walk-all-dots loop, as in a JWT parser.
# It uses the idiom `break if pos.nil?`.
t = "header.payload.sig"
i = 0
positions = ""
while true
  pos = t.index(".", i)
  if pos.nil?
    break
  end
  positions = positions + pos.to_s + ","
  i = pos.to_i + 1
end
puts positions                  # 6,14,
