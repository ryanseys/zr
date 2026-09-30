# `String#setbyte` on a string that is not a literal (from .dup, +, *,
# gsub, etc.) mutates in place.

# Dup'd string: setbyte mutates.
s = "ab".dup
s.setbyte(0, 67)  # 'C'
s.setbyte(1, 68)  # 'D'
puts s   # CD

# String#+ produces a fresh heap buffer too.
s2 = "x" + "y"
s2.setbyte(0, 90)  # 'Z'
puts s2  # Zy
