# `(?xim:...)` inline-flag groups compile and match. The `?` after
# `(` starts a flag list (x / i / m), and `:` starts the
# non-capturing body. A pattern such as `p(/(?x:foo)/.to_s)` must
# not loop without end.

# `(?x:...)` with no whitespace in body. /foo/ matches "foo".
puts (/(?x:foo)/ =~ "foobar").to_s     # 0
puts (/(?x:foo)/ =~ "barbaz").nil?     # true

# `(?:...)` non-capturing still works.
puts (/(?:hello) (?:world)/ =~ "hello world").to_s  # 0

# `(?i:...)` with a body that matches as written.
puts (/(?i:abc)/ =~ "abc").to_s       # 0

# `(?m:...)` similar.
puts (/(?m:foo)/ =~ "foo").to_s       # 0
