# Array#index on an Array of Integers answers an Integer or nil.
# After the nil check, the value is an Integer, and the arithmetic
# on it is plain integer arithmetic.
#
# Sibling of nil_guard_narrows_int_or_nil.rb, which checks the
# same shape on String#index. Both forms behave identically at
# the Ruby level. This example checks the Array of Integers.

ARR = [10, 20, 30, 40, 50]

def offset_or_zero(arr, target)
  i = arr.index(target)
  return 0 if i.nil?
  i + 1
end

puts offset_or_zero(ARR, 30)    # 3
puts offset_or_zero(ARR, 999)   # 0
puts offset_or_zero(ARR, 10)    # 1

# Inspect/.nil? on the Integer-or-nil value.
puts ARR.index(20).inspect      # 1
puts ARR.index(999).inspect     # nil
puts ARR.index(999).nil?        # true
puts ARR.index(20).nil?         # false
