# Regex coverage — five stages plus literal-form tests. Each section
# gives its locals names of its own (`re_s1a`, ...).


re_lv = /[₀₁₂₃₄₅₆₇₈₉]+/
puts re_lv.match?("₁₂")
puts re_lv.match?("abc")
if "abc₁def" =~ re_lv
  puts "lhs match"
else
  puts "lhs miss"
end
if re_lv =~ "abc₁def"
  puts "rhs match"
else
  puts "rhs miss"
end

# Inside a method body — fresh scope, fresh local.
def find(s)
  rx = /[a-z]+/
  rx.match?(s)
end
puts find("hello")
puts find("123")

# Multi-write disqualifies dispatch; the fall-through still compiles.
re2_lv = /a/
re2_lv = "not a regex"
puts re2_lv
