# `defined?` never runs its call, so a call the compiler would rewrite
# (`!x`, `"lit".freeze`, a `require` of a literal name) still answers
# "method", as any other call to a method that exists does.
x = 1
p defined?(!x)
p defined?("a".freeze)
p defined?(require "set")
p defined?(x.nope)
p defined?(!nope_at_all)

