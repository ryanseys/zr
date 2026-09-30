# String#% with a String array RHS does sprintf-style formatting.
# Integer % is still the modulo operator.

# Single placeholder
puts "hello, %s!" % ["world"]            # hello, world!

# Multiple placeholders
puts "%s and %s" % ["a", "b"]            # a and b

# %% literal
puts "100%% of %s" % ["coverage"]        # 100% of coverage

# %s after literal text
puts "[%s][%s][%s]" % ["x", "y", "z"]    # [x][y][z]

# Extra args are ignored (matches CRuby tolerant behavior)
puts "%s" % ["a", "b", "c"]              # a

# Format string with no placeholders, args ignored
puts "no formatting here" % ["x"]        # no formatting here
