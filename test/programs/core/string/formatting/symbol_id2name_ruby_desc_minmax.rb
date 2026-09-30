# Symbol#id2name: the symbol's name as a String (alias of to_s).
p :hello.id2name
p :foo_bar.id2name
puts :sym.id2name.class

# RUBY_DESCRIPTION is a String (value is engine-specific; only the
# class is asserted so it stays portable).
puts RUBY_DESCRIPTION.class

# Range#minmax: [min, max], honouring exclusive end.
p (1..10).minmax
p (1...10).minmax
p (5..5).minmax
