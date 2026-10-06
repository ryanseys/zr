# A raise asks a program's own Exception#backtrace whether the error has
# a backtrace; nil lets the raise take one, and an error in it is dropped.
$exc = nil
class Exception
  undef backtrace
  def backtrace
    $exc = self
  end
end
begin
  raise RuntimeError, "hello"
rescue => e
  p e.equal?($exc)
  p e.message
end
class Exception
  undef backtrace
  def backtrace = nil
end
begin
  raise "again"
rescue => e
  p e.backtrace_locations.nil?
end
class ArgumentError
  def backtrace = ["custom:1"]
end
begin
  raise ArgumentError, "x"
rescue => e
  p [e.backtrace, e.backtrace_locations]
end
class TypeError
  def backtrace = raise("inside")
end
begin
  raise TypeError, "y"
rescue => e
  p [e.class, e.message]
end
