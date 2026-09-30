# `ENV.fetch(key, default)` returns the env value when
# set, otherwise `default`.

# ---- unset / default branch ----

# Literal default.
puts ENV.fetch("DEFINITELY_UNSET_VAR_XYZ_42", "fallback-value")

# Default expression need not be a literal.
default = "computed-default"
puts ENV.fetch("ANOTHER_UNSET_VAR_XYZ_42", default)

# Default by string concatenation.
puts ENV.fetch("THIRD_UNSET_VAR_XYZ_42", "pre-" + "fix")

# ---- set / retrieval branch ----
# The test does not set a var itself. HOME is always exported by
# POSIX `make` and in CI, so the test uses it as the "set" probe. It
# only asserts "non-empty + not the fallback string" so that it
# stays portable across runners (the home value differs per machine).
# If fetch gave the default for a set var, this prints
# "set=fallback-not-used".
home = ENV.fetch("HOME", "fallback-not-used")
if home.length > 0 && home != "fallback-not-used"
  puts "set=ok"
else
  puts "set=" + home
end

# Symmetric: an unset var with a literal default gives the default,
# not an empty string.
maybe = ENV.fetch("DEFINITELY_UNSET_VAR_ABC_99", "fallback-used")
puts "unset=" + maybe
