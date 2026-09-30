# Each inner top-level def has a per-test prefix, so its name is
# unique across the tests.


def t_ewoss_f
  obj = 42
  out = [1, 2, 3].each_with_object([]) { |x, obj| obj.push(x * 2) }
  puts out[0]   # 2
  puts out[1]   # 4
  puts out[2]   # 6
  puts obj      # 42
end
t_ewoss_f
