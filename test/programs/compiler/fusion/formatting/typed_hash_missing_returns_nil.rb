# Bracket access with a missing key on a hash with String values
# returns nil per MRI, not an empty String.

# Symbol keys, String values
puts({a: "hi"}[:missing].inspect)

# String keys, String values
puts({"a" => "hi"}["missing"].inspect)

# Integer keys, String values
puts({1 => "hi"}[99].inspect)

# Existing key still works
puts({a: "hello"}[:a])
