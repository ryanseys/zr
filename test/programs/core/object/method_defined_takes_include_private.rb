# ruby 4.1: method_defined?(name, inherit = true, include_private = false).
# A true third argument also matches a private method; the other
# *_method_defined? forms still take one or two arguments.
def show
  p yield
rescue => e
  p [e.class, e.message]
end

class Base
  private def hidden_base = 1
  protected def guarded = 1
end
class Kid < Base
  private def hidden = 1
  def open = 1
  undef_method :to_s
end
module Pre
  private def pre_private = 1
end
Kid.prepend(Pre)

show { [Kid.method_defined?(:hidden), Kid.method_defined?(:hidden, true, true), Kid.method_defined?(:hidden, false, true)] }
show { [Kid.method_defined?(:hidden_base, true, true), Kid.method_defined?(:hidden_base, false, true), Kid.method_defined?(:hidden_base, true, false)] }
show { [Kid.method_defined?(:guarded, true, nil), Kid.method_defined?(:open, false, false), Kid.method_defined?("open", false, 1)] }
show { [Kid.method_defined?(:to_s, true, true), Kid.method_defined?(:nothing, true, true)] }
show { [Kid.method_defined?(:pre_private, true, true), Kid.method_defined?(:pre_private, false, true)] }
show { [Kid.method_defined?(:initialize, true, true), Kid.method_defined?(:puts, true, true), Kid.method_defined?(:puts)] }
show { Kid.method_defined? }
show { Kid.method_defined?(:a, true, true, true) }
show { Kid.public_method_defined?(:open, true, true) }
show { Kid.private_method_defined?(:hidden, true, true) }
show { Kid.method_defined?(1, true, true) }
show { Module.instance_method(:method_defined?).arity }
