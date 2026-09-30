# Test Regexp support

# match operator
if "hello 123 world" =~ /\d+/
  puts "matched"
end

# match with capture
str = "2024-03-17"
if str =~ /(\d{4})-(\d{2})-(\d{2})/
  puts $1  # 2024
  puts $2  # 03
  puts $3  # 17
end

# String#match?
puts "hello".match?(/ell/)    # true
puts "hello".match?(/xyz/)    # false

# String#gsub with regexp
puts "hello world".gsub(/o/, "0")   # hell0 w0rld

# String#sub with regexp
puts "hello world".sub(/o/, "0")    # hell0 world

# String#scan
"one 1 two 2 three 3".scan(/\d+/) do |m|
  puts m
end
# 1, 2, 3

# String#split with regexp
parts = "a, b,  c".split(/,\s*/)
puts parts.length  # 3
