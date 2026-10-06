# A program's own Exception#backtrace that cannot be called with no
# arguments, or that raises, does not stop a raise: the raise inside it
# does not call it again, as rb_ec_set_raised guards setup_exception.
# One that returns no Array makes $@ and full_message raise TypeError.
class Exception
  undef backtrace
  def backtrace(a)
  end
end
begin
  raise RuntimeError, "hello"
rescue RuntimeError => e
  p e.message
end
p :ok
error_class = Class.new(StandardError) do
  def backtrace = :backtrace
end
begin
  raise error_class
rescue error_class => e
  begin
    $@
  rescue TypeError => t
    p [:dollar_at, t.class]
  end
  begin
    e.full_message
  rescue TypeError => t
    p [:full_message, t.class]
  end
end
raising = Class.new(StandardError) do
  def backtrace = raise("inside backtrace")
end
begin
  raise raising, "outer"
rescue StandardError => e
  p [e.class == raising, e.message]
end
