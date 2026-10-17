# Marshal writes an exception's stored message and backtrace (its hidden
# mesg and bt), whatever `message` or `backtrace` its class writes, so a
# loaded copy is == to it, as minitest's UnexpectedError needs.
class Wrapping < StandardError
  def initialize(error) = (super("Unexpected exception"); @error = error)
  attr_reader :error
  def backtrace = @error.backtrace
  def message = "#{@error.class}: #{@error.message}"
end

stored = ->(e) { [Exception.instance_method(:message).bind_call(e), Exception.instance_method(:backtrace).bind_call(e)] }

inner = RuntimeError.new("Neutered Exception")
inner.set_backtrace(["test.rb:1:in 'run'"])
wrapped = Wrapping.new(inner)
copy = Marshal.load(Marshal.dump(wrapped))
p copy == wrapped, [copy] == [wrapped], stored.(copy), copy.backtrace, copy.message
p Marshal.dump(wrapped)

begin
  raise Wrapping.new(inner)
rescue Wrapping => raised
end
copy = Marshal.load(Marshal.dump(raised))
p copy == raised, stored.(copy) == stored.(raised), copy.backtrace == inner.backtrace

plain = ArgumentError.new("plain")
plain.set_backtrace(%w[a:1 b:2])
copy = Marshal.load(Marshal.dump(plain))
p copy == plain, copy.backtrace, copy.backtrace_locations
p Marshal.dump(plain)
