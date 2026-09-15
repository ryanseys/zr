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


__END__
[Ractor::IsolationError, "can not access instance variables of shareable objects from non-main Ractors"]
#@ stderr
lang/variables/an_ivar_read_of_a_ractor_from_another_ractor_raises_isolation_error.rb:7: warning: Ractor API is experimental and may change in future versions of Ruby.
