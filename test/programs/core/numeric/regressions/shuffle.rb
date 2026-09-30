arr = [1, 2, 3, 4, 5]
s = arr.shuffle
puts s.length
puts s.sort.join(",")
puts arr.join(",")

words = ["foo", "bar", "baz", "qux"]
s2 = words.shuffle
puts s2.length
puts s2.include?("foo")
puts s2.include?("bar")
puts s2.include?("baz")
puts s2.include?("qux")
puts words.join(",")

nums = [10, 20, 30]
nums.shuffle!
puts nums.length
puts nums.sort.join(",")

# FloatArray
floats = [1.5, 2.5, 3.5, 4.5]
fs = floats.shuffle
puts fs.length            # 4
puts floats.length        # 4 (original unchanged)
floats.shuffle!
puts floats.length        # 4 (in-place, length stable)

# Empty / single-element edge cases stay stable.
empty = []
empty.shuffle!
puts empty.length         # 0
one = [42]
one.shuffle!
puts one[0]               # 42
