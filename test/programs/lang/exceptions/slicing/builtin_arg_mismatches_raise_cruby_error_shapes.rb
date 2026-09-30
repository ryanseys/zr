# The table rows validate argument TYPES with CRuby's exact TypeError/
# ArgumentError messages. All are real, rescuable exceptions.

a = ["a"].first
begin
  a + 1
rescue TypeError => e
  puts "TypeError: #{e.message}"
end
arr = [[1]].first
begin
  arr[:x]
rescue TypeError => e
  puts "TypeError: #{e.message}"
end
one = [1].first
begin
  one < "a"
rescue ArgumentError => e
  puts "ArgumentError: #{e.message}"
end
