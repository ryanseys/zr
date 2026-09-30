# The running DEFAULT, rather than a named mark: a bare `private` before the
# `def` stamps the body the same way.
class BD
  private
  def m = "bd1"
end
p [BD.private_instance_methods(false), (BD.new.m rescue $!.class.to_s)]
class BD
  def m = "bd2"
end
p [BD.private_instance_methods(false), BD.new.m]

