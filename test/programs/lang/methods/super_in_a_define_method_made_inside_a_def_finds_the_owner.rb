# super in a method that define_method makes inside another def looks
# up from the new method's owner, not from the def around the block.
def t(l)
  p [l, yield]
rescue StandardError => e
  p [l, e.class, e.message[0, 70]]
end
class Runner
  def plain
    k = Class.new { def hi = :base }
    sub = Class.new(k)
    sub.class_eval { define_method(:hi) { [:sub, super()] } }
    sub.new.hi
  end

  def plain_direct
    k = Class.new { def hi = :base }
    sub = Class.new(k)
    sub.define_method(:hi) { [:sub, super()] }
    sub.new.hi
  end

  def single
    m = Module.new
    m.define_singleton_method(:to_s) { "x" + super() }
    m.to_s[0, 9]
  end

  def single_eval
    m = Module.new
    m.singleton_class.class_eval { define_method(:to_s) { "x" + super() } }
    m.to_s[0, 9]
  end

  def single_feature
    m = Module.new
    m.singleton_class.class_eval { define_method(:append_features) { |mod| super(mod) } }
    Module.new.send(:include, m)
    :ok
  end

  def single_private
    m = Module.new
    m.singleton_class.class_eval { define_method(:extend_object) { |o| super(o) } }
    Object.new.extend(m)
    :ok
  end
end
r = Runner.new
%i[plain plain_direct single single_eval single_feature single_private].each { |n| t(n) { r.send(n) } }
class Runner
  def defined_check
    k = Class.new { def hi = :base }
    sub = Class.new(k)
    sub.define_method(:hi) { defined?(super) }
    sub.define_method(:lo) { defined?(super) }
    [sub.new.hi, sub.new.lo]
  end
end
t(:defined_check) { r.defined_check }
