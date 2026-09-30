# `raise obj, "msg"` where obj's class overrides #exception does not even
# BUILD: codegen hands the constructed object to the raise-argument
# coercion unboxed, where a boxed value is wanted, and the generated program
# is rejected. Any program using this shape fails to compile, so this gap
# "diverges" by failing to produce a binary at all.
class WithHook
  def exception(msg = nil)
    RuntimeError.new("custom exception hook: #{msg}")
  end
end

begin
  raise WithHook.new, "hi"
rescue => e
  puts e.message
end

begin
  raise WithHook.new
rescue => e
  puts e.message
end
