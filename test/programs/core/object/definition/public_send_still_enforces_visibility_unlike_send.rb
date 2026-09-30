# Asserts the CORRECT mechanism: real Ruby resolves visibility at call
# time (`rb_method_call_status`, vm_eval.c:837) and raises a rescuable
# NoMethodError. The program must compile and the raise must be
# catchable, while `send` stays visibility-blind.

class Box
  private

  def secret
    "shh"
  end
end

begin
  puts Box.new.public_send(:secret)
rescue NoMethodError => e
  puts e.message
end
puts Box.new.send(:secret)
