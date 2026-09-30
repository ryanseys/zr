# `"#{sym}"` renders the symbol's name, not an integer id.

s = :hello
puts s
puts "#{s}"
puts s.to_s
puts "x_#{s}_y"

# Multiple symbols + literal mix in one interpolation.
a = :alpha
b = :beta
puts "#{a}-#{b}"

# Symbol from a method return; the call-site infers symbol type
# and the same arm should fire.
def make_sym
  :payload
end
puts "tag=#{make_sym}"
