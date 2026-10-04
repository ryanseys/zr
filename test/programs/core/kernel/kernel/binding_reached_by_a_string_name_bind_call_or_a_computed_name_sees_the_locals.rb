# `binding` and `local_variables` see the caller's locals however they are
# sent: by a String name, through a Method or UnboundMethod, or by a name
# the program computes. `binding` through a Method object has no Ruby
# caller, so it raises.

def show
  p yield
rescue => e
  puts "#{e.class}: #{e.message}"
end

def by_string
  a = 1
  send("binding").local_variable_get(:a)
end

def by_bind_call
  b = 2
  Kernel.instance_method(:local_variables).bind_call(self)
end

def by_method_call
  c = 3
  method(:local_variables).call
end

def binding_by_bind_call
  Kernel.instance_method(:binding).bind_call(self)
end

def by_computed_name(name)
  d = 4
  __send__(name)
end

def by_computed_public_send
  e = 5
  public_send([:local, :variables].join("_"))
end

show { by_string }
show { by_bind_call }
show { by_method_call }
show { binding_by_bind_call }
show { by_computed_name(:local_variables) }
show { by_computed_name("binding").local_variable_get(:d) }
show { by_computed_public_send }

x = 6
show { send(["local", "variables"].join("_")).include?(:x) }
