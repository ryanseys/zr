# In `hash.keys.each do |k|`, the block param shadows an outer local
# of the same name and a different type. The block sees the key, and
# the outer local keeps its own value after the block.

# 1. Outer string `k`, inner Integer key.
def f1
  k = "outer-string"
  h = {1 => "a", 2 => "b"}
  h.keys.each do |k|
    puts k * 10
  end
  puts k
end
f1

# 2. Outer Integer `s`, inner String key.
def f2
  s = 42
  h = {"x" => 1, "y" => 2}
  h.keys.each do |s|
    puts s + "!"
  end
  puts s
end
f2

# 3. Outer String `n`, inner Symbol key.
def f3
  n = "outer"
  h = {a: 10, b: 20}
  h.keys.each do |n|
    puts n
  end
  puts n
end
f3
