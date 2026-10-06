# private_constant, public_constant and private_class_method with no
# name do nothing, and warn when $VERBOSE is true.
class X
  private_constant
  $VERBOSE = true
  private_constant
  public_constant
  private_class_method
  public_class_method
  $VERBOSE = false
end
p X
