# Array#slice! must raise FrozenError on a frozen array, like the other
# mutators.
a = [1, 2, 3]
a.freeze
begin
  a.slice!(0, 1)
  puts "BUG: no raise"
rescue FrozenError
  puts "int slice!"
end

s = ["a", "b", "c"]
s.freeze
begin
  s.slice!(1, 1)
  puts "BUG: no raise"
rescue FrozenError
  puts "str slice!"
end
