# `Object#methods` and `#public_methods` must report a method installed
# on the OBJECT itself, not just what the receiver's CLASS chain
# carries -- and a private one must not wrongly show up in
# `public_methods`.

def try(label)
  p [label, yield]
rescue NoMethodError, NameError => e
  p [label, :raised, e.class.to_s]
end

o = Object.new
class << o
  def pub = :pub
  private
  def hid = :hid
  protected
  def prot = :prot
end
try(:methods_pub)   { o.methods.include?(:pub) }
try(:methods_prot)  { o.methods.include?(:prot) }
try(:methods_hid)   { o.methods.include?(:hid) }
try(:public_pub)    { o.public_methods.include?(:pub) }
try(:public_hid)    { o.public_methods.include?(:hid) }
try(:public_prot)   { o.public_methods.include?(:prot) }
try(:public_false)  { o.public_methods(false).sort }
try(:private_false) { o.private_methods(false).include?(:hid) }
try(:prot_false)    { o.protected_methods(false) }

module MFa
  module_function
  def helper = :helper
end
e = Object.new.extend(MFa)
try(:ext_methods)   { e.methods.include?(:helper) }
try(:ext_private)   { e.private_methods(false).include?(:helper) }
