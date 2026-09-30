# An initialize parameter that is never written to an ivar still gets
# the value from the `Foo.new(...)` call site, here a String.

class T_initialize_param_through_call_Greeter
  def initialize(name)
    puts name
  end
end

T_initialize_param_through_call_Greeter.new("hello")
