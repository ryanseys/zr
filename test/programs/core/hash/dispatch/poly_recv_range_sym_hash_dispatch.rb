# Two calls on built-in container types whose receiver type is known
# only at run time.
#
# 1. `case x; when Range; r.include?(x); end` -- a value narrowed to a
#    Range via case/when answers include? as a Range.
#
# 2. A lookup in a Symbol-keyed hash with a key narrowed by
#    `is_a?(Symbol)`. The key can be a Symbol at run time.
#
# Also inspect on a Range read out of a hash with mixed values
# answers "200..299", not "#<Object>".

# --- 1: case/when narrowing to Range, then include?.
def check_range(value, actual)
  case value
  when Range
    value.include?(actual)
  when Integer
    value == actual
  else
    false
  end
end

puts check_range(200..299, 200)   # true
puts check_range(200..299, 300)   # false
puts check_range(200..299, 250)   # true
puts check_range(404, 404)        # true
puts check_range(404, 200)        # false

# --- 2: sym-keyed hash with a key that comes from a
# Symbol|Integer narrowing.
H = { a: 200..299, b: 404, c: 500 }

def lookup(expected)
  expected.is_a?(Symbol) ? H[expected] : expected
end

puts lookup(:a).inspect           # 200..299
puts lookup(:b).inspect           # 404
puts lookup(:c).inspect           # 500
puts lookup(503).inspect          # 503
