# `CONST ||= v` on a constant that was NEVER assigned defines it quietly,
# and does not raise `NameError`. Real `ruby` confirms that this is a
# narrow special case: ONLY `||=` gets this leniency. `+=`/`&&=` on the
# same undefined constant still raise (see the next test).

MAX ||= 100
puts MAX
MAX ||= 200
puts MAX
