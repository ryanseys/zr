# A call of method_missing where the class undefined it raises for the
# name that the first argument gives, and a name that is no Symbol is an
# ArgumentError.
def t
  yield
rescue => e
  puts "#{e.class}: #{e.message.sub(/0x\h+/, "0xADDR")}"
end
c = Class.new { undef_method(:method_missing) }
t { c.new.method_missing }
t { c.new.method_missing(:foo) }
t { c.new.method_missing(2) }
t { 1.instance_eval { method_missing(1) } }
t { 1.instance_eval { method_missing(:method_missing) } }
