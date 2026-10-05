# A width or precision too big for an int raises ArgumentError, also a
# star width of INT_MIN, which has no positive int.
def t(l)
  p [l, yield]
rescue StandardError => e
  p [l, e.class, e.message]
end
t(1) { sprintf("%*999999999999999999999999999999999999999999999999999999999999$d", 1) }
t(2) { sprintf("%.*999999999999999999999999999999999999999999999999999999999999$d", 1) }
t(3) { sprintf("%*s", -2147483648, "") }
t(4) { sprintf("%*s", 2147483648, "") }
t(5) { sprintf("%*d", -3, -1) }
t(6) { sprintf("%99999999999999999999d", 1) }
