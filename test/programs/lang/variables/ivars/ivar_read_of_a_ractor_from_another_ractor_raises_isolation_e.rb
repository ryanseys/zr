# Reading an instance variable of a Ractor from a non-main ractor is an
# IsolationError, and the raise must leave `@peek` with no value at
# all: the read is a call the runtime checks like any other.
class Ractor
  def peek = [@peek, :after]
end
r = Ractor.new do
  begin
    Ractor.current.peek
  rescue Ractor::IsolationError => e
    [e.class, e.message]
  end
end
p r.value


