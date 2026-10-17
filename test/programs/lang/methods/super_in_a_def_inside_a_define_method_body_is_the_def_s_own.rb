# A def written in a define_method body shares the body's cref, but it
# is a method of its own: its super, zsuper and defined?(super) go on
# from the def, not from the define_method method.
class Base
  def greet(name) = "base #{name}"
  def to_s = "a base"
end

class Child < Base
  define_method(:greet) { |name| "child " + super(name) }

  define_method(:singleton) do
    s = +"text"
    def s.inspect = "<" + super + ">"
    def s.upcase(*) = super().reverse
    def s.size = [1].map { super() + 100 }.first
    def s.probe = [defined?(super), defined?(inspect)]
    [s.inspect, s.upcase, s.size, s.probe]
  end

  define_method(:instance_def) do
    def to_s = "child of " + super
    to_s
  end

  def outer
    self.class.send(:define_method, :inner) do
      o = Object.new
      def o.to_s = "object: " + super.split(":").first
      [o.to_s, greet("x")]
    end
    inner
  end
end

c = Child.new
p c.greet("bo")
p c.singleton
p c.instance_def
p c.outer

class Child
  define_method(:after) do
    a = +"z"
    def a.frozen? = !super
    a.frozen?
  end
end
p c.after
