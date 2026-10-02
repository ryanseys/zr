# `raise Cls` runs an initialize that the program wrote for a core
# exception class; an exception the runtime raises itself keeps its own.
class KeyError
  def initialize(msg = "no key", receiver: nil, key: nil)
    super("wrapped: #{msg}")
  end
end

begin
  raise KeyError, "x"
rescue KeyError => e
  p e.message
end
begin
  raise KeyError
rescue KeyError => e
  p e.message
end
begin
  {a: 1}.fetch(:zz)
rescue KeyError => e
  p e.message
end

# A finalizer that raises gets ruby's warning, then its error, and the
# program goes on.
boom = Object.new
ObjectSpace.define_finalizer(boom, proc { |_id| raise "ignored" })
puts "end"
