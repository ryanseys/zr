# Assigning a constant that already has a value warns TWICE on stderr -- once
# at the new assignment, once naming where the previous one was.
#
# CRuby is deliberate about which writes are quiet: a `remove_const` first
# clears the record, and a `class`/`module` reopen creates nothing, so neither
# warns. Only a genuine second assignment does.

D = 1
D = 2
p D

module M
  E = 1
  E = 2
end

F = 3
Object.send(:remove_const, :F)
F = 4

class C; end
class C; end

G = 5
Object.const_set(:G, 6)
