# CRuby lists a class's methods in the order of its method table, an id
# table keyed by the methods' symbol serials, so Kernel's come in an order
# that its C and Ruby definitions make together. zr lists them in the
# order its core defines them. Where two names tie, did_you_mean suggests
# the one listed first: `loc` gives `loop` in CRuby.
p Kernel.private_instance_methods(false).first(6)
m = Object.new.private_methods
p m.index(:loop) < m.index(:load)
begin
  loc
rescue NameError => e
  puts e.detailed_message(highlight: false).lines.last
end
