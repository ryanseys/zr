# BasicObject#method_missing leaves its own frame before it raises
# NoMethodError, so a `super` from a program's method_missing, a send and
# a bound call each start the backtrace at their caller. A bad name
# raises ArgumentError from the method's frame.
class Ghost
  def method_missing(name, *args)
    name == :known ? :found : super
  end
end

def labels(error) = error.backtrace_locations.map(&:label)

[
  -> { Ghost.new.hidden },
  -> { Object.new.__send__(:method_missing, :zz) },
  -> { Object.new.zz },
  -> { BasicObject.instance_method(:method_missing).bind_call(Object.new, :q) },
  -> { Object.new.method(:method_missing).call(:w) },
  -> { BasicObject.instance_method(:method_missing).bind_call(Object.new) },
  -> { BasicObject.instance_method(:method_missing).bind_call(Object.new, "s") },
].each do |code|
  code.call
rescue NoMethodError, ArgumentError => e
  p [e.class, labels(e)]
end
p Ghost.new.known
