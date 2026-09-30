# A parameter's use in the method body tells its type:
#
# A. Array calls on the parameter: `push`, `pop`, `shift`, `unshift`,
#    `concat`, `compact`, `flatten`, `transpose`. The operators `<<`,
#    `&`, `|`, `*`, `+` and `-` do not count, because Integer also
#    has them.
#
# B. Hash calls on the parameter: `keys`, `values`, `each_pair`,
#    `merge`, `has_key?`, `fetch`, `store`, `delete`,
#    `transform_values`, `transform_keys`, `to_h`. Array, String and
#    Integer do not have these methods, so they show a Hash.
#
# Each caller passes a literal argument, because `nil.push` raises
# NoMethodError in Ruby.

# Array body inference - typed caller via an array literal.
def consume_arr(arr)
  arr.push(42)
  puts "arr.length=" + arr.length.to_s
end

consume_arr([])

# Hash iteration inference -- .each + .merge / .keys + [k].
def merge_into_seed(other)
  result = {a: 1}
  other.each { |k, v| result[k] = v }
  result.keys.length
end

puts merge_into_seed({b: 2, c: 3})

# A Hash parameter shown only by `.keys` (no `.each`, no literal key),
# as in an adapter's insert: `cols = attrs.keys;
# cols.map { |k| attrs[k] }`. The `[k]` key is computed, not a literal.
def hash_keys_count(h)
  h.keys.length
end

puts hash_keys_count({a: 1, b: 2})
