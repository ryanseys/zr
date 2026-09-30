# An empty `[]` followed by `push(:sym)`: element access gives the
# Symbols, and `puts` prints their names.

syms = []
syms.push(:tag)
syms.push(:more)
puts syms[0]      # tag
puts syms[1]      # more
puts syms.length  # 2

# `<<` form should behave the same.
syms2 = []
syms2 << :alpha
syms2 << :beta
puts syms2[0]     # alpha
puts syms2[1]     # beta
