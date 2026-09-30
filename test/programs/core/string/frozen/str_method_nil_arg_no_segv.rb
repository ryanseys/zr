# String methods called with no argument raise ArgumentError, as in CRuby.
# The first call, `"foo".count`, raises. `rescue TypeError` does not
# catch an ArgumentError, so the program stops there.

# count / rindex / include? / start_with? / end_with? with no arg.

begin
  "foo".count
  puts "BUG count: no raise"
rescue TypeError => e
  puts "count: #{e.message}"
end
p "foo".delete   # ArgumentError
p "foo".rindex(/missing/)  # nil
p "abcdabcd".rindex(/c/)   # 6
begin
  "foo".send(:<<)          # ArgumentError
  puts "no raise"
rescue FrozenError => e
  puts "send-lshift: " + e.message
end

# setbyte on a literal: WITHOUT the frozen_string_literal magic comment a
# literal is mutable (CRuby), so the write changes it. A frozen-string-literal
# file or an explicit .freeze still raises.

(str = "a")
begin
  str.setbyte(0, 98)
  puts "literal not frozen: " + str
rescue FrozenError => e
  puts "frozen literal: " + e.message
end
str2 = "a".dup
str2.setbyte(0, 98)
puts str2  # "b" (heap, mutates)
