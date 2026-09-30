# `s[i..i] == "/"` takes a Range subscript and compares the substring,
# as `s[i] == "/"` does for one Integer index. The 2-arg
# `s[start, len]` form works the same way.

s = "abc/def"
i = 3
if s[i..i] == "/"
  puts "match"
end

# Range literal as the [] arg (no LV indirection).
puts s[1..2]            # "bc"
puts s[3..3] == "/"     # true

# Exclusive range.
puts s[3...4] == "/"    # true

# `s[start, len]` 2-arg form must also fall through cleanly.
puts s[3, 1] == "/"     # true
