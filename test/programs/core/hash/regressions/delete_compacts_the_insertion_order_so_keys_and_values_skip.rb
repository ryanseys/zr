# After Hash#delete, #keys / #values / each iteration skip the deleted
# entry and keep the insertion order of the other entries.

# String keys
sh = {"a" => 1, "b" => 2, "c" => 3}
sh.delete("b")
puts sh.keys.inspect          # ["a", "c"]
puts sh.values.inspect        # [1, 3]
puts sh.length                # 2

# Symbol keys
yh = {a: 1, b: 2, c: 3}
yh.delete(:b)
puts yh.keys.inspect          # [:a, :c]
puts yh.values.inspect        # [1, 3]

# Delete first / last entries (boundary cases for the shift loop)
fh = {a: 1, b: 2, c: 3}
fh.delete(:a)
puts fh.keys.inspect          # [:b, :c]

lh = {a: 1, b: 2, c: 3}
lh.delete(:c)
puts lh.keys.inspect          # [:a, :b]
