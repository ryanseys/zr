# `SomeClass.extend(M)` copies M's instance methods in as CLASS methods and
# must keep their visibility marks -- the class-receiver twin of the
# "extended module keeps its visibility" test. A `module_function` name
# -- private on the module's instance side -- must not arrive public
# on the class's singleton.

def try(label)
  p [label, yield]
rescue NoMethodError, NameError => e
  p [label, :raised, e.class.to_s]
end

module MFc
  module_function
  def helper = :helper
end
class KD; end
KD.extend(MFc)
try(:dot)      { KD.helper }
try(:public)   { KD.public_send(:helper) }
try(:send)     { KD.send(:helper) }
try(:singles)  { KD.singleton_methods }
try(:respond)  { KD.respond_to?(:helper) }

module M1
  def m = :m
  private :m
end
class C2; end
C2.extend(M1)
try(:m_dot)    { C2.m }
try(:m_public) { C2.public_send(:m) }
try(:m_singles){ C2.singleton_methods }
try(:m_priv)   { C2.singleton_class.private_instance_methods(false) }

# A public row still arrives public, and an own `def self.x` beside it is
# untouched.
module M2
  def pub2 = :pub2
end
class C3
  extend M2
  def self.own = :own
end
try(:pub_dot)  { C3.pub2 }
try(:own_dot)  { C3.own }
try(:c3_sing)  { C3.singleton_methods.sort }
