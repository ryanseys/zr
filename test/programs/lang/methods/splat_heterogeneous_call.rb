# Call sites of a `def f(*args)` method pass args of different types.
# `args` holds each value with its own type, so `puts x.to_s` prints
# the Strings as Strings, not as large Integers.

def test_splat(*args)
  args.each { |x| puts x.to_s }
end

test_splat(1, 2, 3)
test_splat("a", "b")
