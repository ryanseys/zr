# `obj.extend(M)` puts M in the singleton class's SUPER chain, so
# `obj.singleton_class.instance_methods(false)` must NOT list names
# that belong to the module. An own `def obj.x` defined beside the
# extend must still show up in the narrow form.
#
# `singleton_methods` is deliberately NOT part of this: CRuby's wide form does
# report an extended module's methods, and only the narrow `false` form skips
# them.

def try(label)
  p [label, yield]
rescue NoMethodError, NameError => e
  p [label, :raised, e.class.to_s]
end

module Plain
  def pn = :pn
end
r = Object.new.extend(Plain)
try(:own_im)     { r.singleton_class.instance_methods(false) }
try(:anc)        { r.singleton_class.ancestors[1].to_s }
try(:wide_sing)  { r.singleton_methods }
try(:call)       { r.pn }

# An own `def obj.x` beside the extend stays own.
def r.mine = :mine
try(:own_after)  { r.singleton_class.instance_methods(false) }

module Plain2
  def qn = :qn
end
s = Object.new
s.extend(Plain, Plain2)
try(:two_own)    { s.singleton_class.instance_methods(false) }
try(:two_anc)    { s.singleton_class.ancestors[1, 2].map(&:to_s) }
