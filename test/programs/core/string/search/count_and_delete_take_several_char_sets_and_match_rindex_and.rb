# `count`/`delete` take one OR MORE char-set specs (intersected, `^`
# negation honored); `match`/`match?`/`rindex` take an optional start
# position; `rindex` also accepts a Regexp; `each_line` an optional
# separator; `split` an optional limit (positive caps fields, negative
# keeps trailing empties). All oracle-verified against ruby 4.0.7.

p "hello world".count("lo")
p "hello world".count("lo", "o")
p "hello world".count("^l", "lo")
p "hello".rindex("l", 2)
p "hello".rindex("l", 3)
p "abcdabcd".rindex(/c/)
p "hello".rindex(/l/, 2)
p "hello".match?(/e/, 1)
p "hello".match?(/o/, -1)
r = "hello".match(/l/, 3); p(r && r[0])
p "1-2-3".each_line("-").to_a
p "a,b,c".split(",", 2)
p "a,b,,".split(",")
p "a,b,,".split(",", -1)
p "a1b2c3".split(/\d/, 2)
