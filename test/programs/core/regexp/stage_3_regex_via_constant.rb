# Regex coverage — five stages plus literal-form tests. Each section
# gives its locals names of its own (`re_s1a`, ...).


RX = /[₀₁₂₃₄₅₆₇₈₉ₐₑₒₓₔ]+/
puts RX.match?("₁₂")
puts RX.match?("abc")
if "₁₂" =~ RX
  puts "lhs match"
else
  puts "lhs miss"
end
if RX =~ "₁₂"
  puts "rhs match"
else
  puts "rhs miss"
end
m_s3 = RX.match("₁₂")
puts m_s3 ? "match ok" : "match fail"
