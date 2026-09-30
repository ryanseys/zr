# Numeric / byte query methods on a poly value (a boxed element of a
# heterogeneous array): nan? / finite? / infinite? / abs / floor / ceil /
# round / truncate / zero? / positive? / negative? / bytesize / ord /
# bit_length / getbyte dispatch on the class of the value at runtime, as in
# CRuby.
#
# NOTE: no class in this program may define a method or reader with one
# of these names.

# A Float read out of a mixed Array.
v = [1.5, "x"][0]
puts v.to_i        # 1
puts v.nan?        # false
puts v.abs         # 1.5
puts v.floor       # 1
puts v.ceil        # 2
puts v.round       # 2
puts v.truncate    # 1
puts v.zero?       # false
puts v.positive?   # true
puts v.negative?   # false
puts v.finite?     # true
p v.infinite?      # nil

# Negative float: round is half-away-from-zero, truncate goes toward zero
w = [-2.5, "x"][0]
puts w.abs         # 2.5
puts w.floor       # -3
puts w.ceil        # -2
puts w.round       # -3
puts w.truncate    # -2
puts w.negative?   # true

# Integer carried in a poly slot: floor/ceil/round return self
n = [-3, "x"][0]
puts n.abs         # 3
puts n.floor       # -3
puts n.round       # -3
puts n.zero?       # false
puts n.positive?   # false
puts n.finite?     # true
p n.infinite?      # nil

z = [0, "x"][0]
puts z.zero?       # true
puts z.positive?   # false
puts z.negative?   # false
puts z.bit_length  # 0
puts n.bit_length  # 2

# String carried in a poly slot: byte/codepoint queries
s = ["ab", 1][0]
puts s.getbyte(0)  # 97
puts s.getbyte(1)  # 98
puts s.getbyte(-1) # 98
p s.getbyte(5)     # nil (out of range)
puts s.bytesize    # 2
puts s.ord         # 97

# Non-finite floats: rounding raises FloatDomainError (not C UB), abs works
nan = [0.0 / 0.0, "x"][0]
inf = [-1.0 / 0.0, "x"][0]
begin
  nan.floor
rescue FloatDomainError => ex
  puts "#{ex.class}: #{ex.message}"   # FloatDomainError: NaN
end
begin
  inf.round
rescue FloatDomainError => ex
  puts "#{ex.class}: #{ex.message}"   # FloatDomainError: -Infinity
end
puts nan.abs.nan?  # true
puts inf.finite?   # false
p inf.infinite?    # -1

# Empty string: bytesize 0; ord raises CRuby's ArgumentError
es = ["", 1][0]
puts es.bytesize   # 0
begin
  es.ord
rescue ArgumentError => ex
  puts "#{ex.class}: #{ex.message}"   # ArgumentError: empty string
end
