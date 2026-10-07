# The NoMethodError or NameError that the base method_missing or
# const_missing raises goes through rb_exc_raise, which sends `exception`
# and `backtrace` to it: a :c_call TracePoint sees both, after the
# :c_return of method_missing or const_missing. A `super` from the
# program's own method_missing gives the same events.
class Answering
  def method_missing(name, *) = name == :hello ? :hi : super
  def respond_to_missing?(*) = true
end

class Secretive
  private def hidden = 1
end

def events
  seen = []
  TracePoint.new(:c_call, :c_return) do |tp|
    seen << [tp.event, tp.method_id, tp.defined_class, tp.self.class] if tp.path == __FILE__
  end.enable do
    yield
  rescue NameError
    nil
  end
  seen
end

p events { nil.nope }
p events { Secretive.new.hidden }
p events { Answering.new.nope }
p events { Answering.new.hello }
p events { UndefinedHere }
p events { Answering::Missing }
