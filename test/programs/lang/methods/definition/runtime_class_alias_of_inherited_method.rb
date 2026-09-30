# `Class.new(Base)`, where `Base` is a previously defined class, must be
# able to run every method it inherits, including a method reached
# through `alias_method`, and its instances must support instance
# variables.
#
# A builtin root (`Class.new(String)`) must keep working the same way.
#
# A body written inside the `Class.new` block is unaffected: those become
# runtime overlay entries, which take their receiver as an argument.

class Base
  def greet = "base"
  def with_ivar
    @x = 1
    "iv#{@x}"
  end
end

# The plain case -- no alias anywhere.
Plain = Class.new(Base)
p Plain.new.greet
p Plain.new.with_ivar

# The alias case, which is how this was first found.
Sub = Class.new(Base) do
  alias_method :old_greet, :greet
  def greet = "new+" + old_greet
end

p Sub.new.greet
p Sub.new.old_greet
p Sub.instance_method(:old_greet).owner

# A builtin root already bridges, and must keep working.
Tagged = Class.new(String)
p Tagged.new("hi").upcase
p Tagged.new("hi").class == Tagged
