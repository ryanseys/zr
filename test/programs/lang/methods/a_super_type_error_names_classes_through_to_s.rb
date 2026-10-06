# The TypeError of a super whose self is no instance of the method's
# class names both classes through their own to_s.
def labeled(name, base = Object, &body)
  Class.new(base) do
    singleton_class.class_eval do
      define_method(:to_s) { name }
      alias_method :inspect, :to_s
    end
    class_eval(&body) if body
  end
end
sup = labeled("Super\u{30af}") { def foo = :super }
sub = labeled("Sub\u{30af}", sup) do
  def foo
    Object.new.instance_eval { super() }
  end
end
begin
  sub.new.foo
rescue TypeError => e
  p e.message.sub(/#<Object:0x\h+>/, "OBJ")
end
