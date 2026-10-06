# Regex coverage — five stages plus literal-form tests. Each section
# gives its locals names of its own (`re_s1a`, ...).


puts(("₁" =~ /[₀-₉]/) ? "ok1" : "fail1")
puts(("α" =~ /[α-ω]/) ? "ok2" : "fail2")
puts(("abc₁def" =~ /[₀₁₂₃₄₅₆₇₈₉]+/) ? "ok3" : "fail3")
puts(("a"  =~ /[^₀-₉]/) ? "ok4" : "fail4")
puts(("₁" =~ /[^₀-₉]/) ? "fail5" : "ok5")
puts(("z"  =~ /[a-z₀-₉]/) ? "ok6" : "fail6")
puts(("₅" =~ /[a-z₀-₉]/) ? "ok7" : "fail7")
puts(("₁" =~ /[α-ω]/) ? "fail8" : "ok8")
puts(("a"  =~ /[α-ω]/) ? "fail9" : "ok9")
m_s2 = "abc₁₂₃def" =~ /[₀-₉]+/
puts(m_s2 ? "ok10" : "fail10")
m_s2_index = "abc" =~ /b/
puts m_s2_index + 10
if ("abc" =~ /z/) && true
  puts "fail11"
else
  puts "ok11"
end
