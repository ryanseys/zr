# `public :name` in a module finds a method that Object defines, and
# gives the module a public copy, as rb_export_method does.
class Object
  def from_object = :object
  private :from_object
end
module Kernel
  public :from_object
end
p [Kernel.public_method_defined?(:from_object), Object.private_method_defined?(:from_object)]
module Plain; end
begin
  Plain.send(:public, :no_such_method_anywhere)
rescue NameError => e
  p e.message
end
