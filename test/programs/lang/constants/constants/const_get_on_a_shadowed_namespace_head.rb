# `Klass.const_get(:NAME)` must resolve correctly even when a namespace
# segment is shadowed by a nested class or module of the same name.
#
# appraisal2 3.2.2 is the shape: a module with a same-named class nested
# inside it. Resolving the head segment `Appraisal` from inside `module
# Appraisal` must not stop at the nested CLASS, which has no `Hooks` --
# `Appraisal::Hooks` must still resolve, the same as the gem's own
# anchored form `::Appraisal::Hooks`.
module Sample
  # The shadow: `Sample::Sample`, so the head segment resolves to a class that
  # knows nothing about the modules beside it.
  class Sample
  end

  module Hooks
    GEMFILE = "Gemfile"
  end

  class << self
    def gemfile = ::Sample::Hooks.const_get(:GEMFILE)
  end
end

p Sample.gemfile

# When the shadowing class also answers the name, nothing raises, and
# the read must still resolve against the RIGHT owner, not read the
# wrong constant.
module Twin
  class Twin
    module Inner
      VALUE = :from_the_nested_class
    end
  end

  module Inner
    VALUE = :from_the_module
  end

  class << self
    def value = ::Twin::Inner.const_get(:VALUE)
    def nested = ::Twin::Twin::Inner.const_get(:VALUE)
  end
end

p Twin.value
p Twin.nested

# The same read spelled every other way must agree.
p Twin::Inner.const_get(:VALUE)
p Twin::Inner::VALUE
p Twin::Inner.const_defined?(:VALUE)
p Sample::Hooks.const_get(:GEMFILE)

# And an unqualified reference from inside the shadowed namespace still means
# what Ruby says it means.
module Twin
  def self.from_inside = Inner.const_get(:VALUE)
end
p Twin.from_inside
