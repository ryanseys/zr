# This dynamic-dispatch trampoline backs both a user CLASS method reached
# dynamically and a reopened-builtin instance method. On an arity
# mismatch it raises a rescuable ArgumentError. Oracle-verified.

class A
  def self.cm(a, b) = a + b
end
class Integer
  def double(a); self * 2; end
end
k = A
begin
  k.send(:cm, 1)
rescue ArgumentError => e
  puts "cm: #{e.message}"
end
begin
  5.send(:double)
rescue ArgumentError => e
  puts "double: #{e.message}"
end
puts "survived"
