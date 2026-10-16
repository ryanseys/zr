# Exception defines method_missing and respond_to_missing? again with
# BasicObject's and Kernel's own C functions, so a missing method of an
# exception raises from its caller's frame, and reflection shows both.
p Exception.private_instance_methods(false).sort
p [Exception.instance_method(:method_missing).arity, Exception.instance_method(:respond_to_missing?).arity]
p Exception.instance_method(:method_missing).owner
p StandardError.new.respond_to?(:nothing_here)

def call_missing
  RuntimeError.new("x").nothing_here
rescue NoMethodError => e
  p [e.message, e.name, e.backtrace_locations.map(&:label)]
end
call_missing
begin
  ArgumentError.new.send(:method_missing, :other, 1)
rescue NoMethodError => e
  p [e.message, e.args, e.backtrace_locations.first.label]
end
error = Class.new(StandardError) do
  def method_missing(name, *args) = name == :known ? [:known, args] : super
  def respond_to_missing?(name, include_private) = name == :known || super
end.new
p error.known(1)
p [error.respond_to?(:known), error.respond_to?(:other)]
begin
  error.other
rescue NoMethodError => e
  p [e.message, e.backtrace_locations.map(&:label)]
end
RuntimeError.new.zzz
