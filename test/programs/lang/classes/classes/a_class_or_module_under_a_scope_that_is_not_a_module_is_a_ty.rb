# The scope of `class A::B` or `module A::B` must be a class or a
# module, as for a constant read.
X = 12
[-> { class X::C; end }, -> { module X::M; end }, -> { class nil::Foo; end },
 -> { class "s"::C < Object; end }].each do |f|
  f.call
rescue TypeError => e
  p e.message
end
