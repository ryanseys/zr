# rb_builtin_class_name: a refusal names nil, true and false by themselves
# rather than by their classes, and an anonymous class by the path
# `#<Class:0x...>` rather than by a name it has none of.
#
# zr interpolated the class at about 76 sites, so `[1] - nil` said
# "NilClass" where ruby says "nil", and a value of an anonymous class said
# nothing at all, because `Class#name` answers nil for one.
#
# Both message families follow the rule: "no implicit conversion of X into Y"
# and "wrong argument type X (expected Y)".

def refusal
  answer = yield
  "no refusal: #{answer.inspect}"
rescue StandardError => e
  "#{e.class}: #{e.message}"
end

# no implicit conversion, over the three values that name themselves
puts refusal { [1] - nil }
puts refusal { [1] - true }
puts refusal { [1] - false }
puts refusal { {}.merge(false) }
puts refusal { "a" + nil }
puts refusal { "a" * nil }

# wrong argument type, the same rule
puts refusal { Module.new.include(nil) }
puts refusal { Module.new.include(true) }
puts refusal { Struct.new(:a).new(1).values_at(true) }

# Kernel's own conversions
puts refusal { Integer(nil) }
puts refusal { Integer(false) }
puts refusal { Float(nil) }
puts refusal { String(nil).class }

# An ordinary class still names itself.
puts refusal { [1] - 3.5 }
puts refusal { Module.new.include(Object.new.freeze.class.new) }

# An anonymous class has no name, so the refusal carries its path. The
# address is the object's own, so only the shape is asserted here.
anonymous = Class.new.new
begin
  [1] - anonymous
rescue TypeError => e
  p e.message.start_with?("no implicit conversion of #<Class:0x")
  p e.message.end_with?("> into Array")
end
begin
  Module.new.include(anonymous)
rescue TypeError => e
  p e.message.start_with?("wrong argument type #<Class:0x")
  p e.message.end_with?("> (expected Module)")
end

