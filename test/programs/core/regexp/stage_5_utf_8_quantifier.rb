# Regex coverage — five stages plus literal-form tests. Each section
# gives its locals names of its own (`re_s1a`, ...).


puts "abc₁₂def".gsub(/[₀-₉]+/, "N")
puts "abc₁₂₃def".gsub(/[₀-₉]+/, "N")
puts "₁abc₂₃def₄₅₆".scan(/[₀-₉]+/).length
puts "₀₁".match?(/[₀-₉]{2}/) ? "ok2" : "fail2"
puts "₀".match?(/[₀-₉]{2}/) ? "fail3" : "ok3"
puts "a₁b₂c".scan(/[a-z₀-₉]+/).length
puts "₁₂₃".scan(/[₀-₉]/).length
puts "αβ".match?(/[α-ω]+/) ? "ok7" : "fail7"
