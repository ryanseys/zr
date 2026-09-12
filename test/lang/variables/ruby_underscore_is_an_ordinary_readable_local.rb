# Ruby's `_` is an ordinary local: it reads back, it reassigns from its own
# value, and only the first `_` in a parameter list owns the name. The
# generated program has no named binding that spells `_`, so it must be
# mangled.

_ = 10
p _
_ = _ + 5
p _
[[1, :a]].each { |n, _| p n }
[[1, :a]].each { |_, sym| p sym }
_, second = [:first, :second]
p [second, _]
__END__
10
15
1
:a
[:second, :first]
