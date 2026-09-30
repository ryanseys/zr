# A Time value in a hash or array that also holds Integers. The printed
# form of a Time depends on the timezone, so the example does not print
# the Time values. It checks the Integer values and the sizes.

H = {
  start: Time.at(0),
  middle: Time.at(1234567890),
  count: 42,
  limit: 100,
}

puts H[:count]                # 42
puts H[:limit]                # 100
puts H.length                 # 4
puts H.has_key?(:start)       # true
puts H.has_key?(:missing)     # false

# Mixed poly array: Time + Int — verify the int slots still
# round-trip and the Time slots don't break the array shape.
arr = [Time.at(0), 100, Time.at(1234567890), 200]
puts arr.length               # 4
puts arr[1]                   # 100
puts arr[3]                   # 200
