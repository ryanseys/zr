# lrama-required features, in three parts of one coverage matrix.



# private (should be ignored)
class Foo
  def pub; "public"; end
  private
  def priv; "private"; end
end
f = Foo.new
puts f.pub

# bare case (case without expression)
x = 5
result_x = case
           when x > 10 then "big"
           when x > 3 then "medium"
           else "small"
           end
puts result_x

# Array.new(n, val)
arr_new = Array.new(5, 42)
puts arr_new.length  # 5
puts arr_new[0]      # 42
puts arr_new[4]      # 42

# Array#compact (no-op for IntArray)
a2 = [1, 2, 3]
puts a2.compact.length  # 3

# Array#flatten (no-op for IntArray)
puts a2.flatten.length  # 3

# Array#unshift
a3 = [2, 3, 4]
a3.unshift(1)
puts a3[0]  # 1
puts a3.length  # 4

# Array#reverse
a4 = [1, 2, 3]
rev = a4.reverse
puts rev[0]  # 3
puts rev[2]  # 1

# Float::INFINITY
puts Float::INFINITY > 999999  # true

puts "done"
