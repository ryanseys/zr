# A `return` in a block in a class body at the toplevel has no method to
# leave. A `defined?` whose value is unused runs nothing, and a scoped
# constant tests its scope without const_missing.
$stderr = $stdout
def y = yield

begin
  class Foo
    $y = 1
    1.times { return }
    $y = 2
  end
rescue LocalJumpError => e
  p [:times, e.message, e.reason, $y]
end

begin
  module Bar
    class Baz
      y { y { return 3 } }
    end
  end
rescue LocalJumpError => e
  p [:yield, e.message, e.exit_value]
end

module DS
  def self.side_effects = ($x = :executed)
end
$x = :not_executed
defined?(DS.side_effects / 2)
p $x
p defined?(DS.side_effects / 2)
p $x

class << Object
  def const_missing(name) = (p [:const_missing, name]; super)
end
p defined?(Undefined::Object)
p defined?(DS::Undefined::Undefined)
p defined?(DS::Undefined)
p defined?(DS::Undefined.to_s)
p defined?(::DS)
