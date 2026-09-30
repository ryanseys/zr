# String#squeeze with multiple args squeezes runs of chars in the
# intersection of the charsets.
p "aaabbbccc".squeeze("a", "b")
p "aaabbbccc".squeeze("a", "ab")
p "aaabbbccc".squeeze("abc")
p "aaabbbccc".squeeze
