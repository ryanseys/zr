# The sweep. Each shape below is one a fix could plausibly get wrong.

# `protected` is the third mark, and it rides the same two bits.
class PR
  def m = "pr1"
  protected :m
end
p [PR.protected_instance_methods(false), (PR.new.m rescue $!.class.to_s)]
class PR
  def m = "pr2"
end
p [PR.protected_instance_methods(false), PR.new.m]

