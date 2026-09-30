# `defined?(expr)` gives a tag string: "local-variable" /
# "instance-variable" / "constant" / "method" / "expression". It gives
# nil for an undefined name, and `puts` prints nil as an empty line.

puts defined?(undefined_local)
z = 1
puts defined?(z)
puts defined?(@undef_ivar)
puts defined?(Object)
puts defined?(undefined_method)
puts defined?(nil)
puts defined?(self)

@written_ivar = "x"
puts defined?(@written_ivar)
