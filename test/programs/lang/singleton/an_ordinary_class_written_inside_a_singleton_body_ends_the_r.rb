# `class << self` inside `class << self` opens the SINGLETON's own singleton --
# the same construct one level deeper, so it takes the same route one level
# deeper. Its body becomes a reopen of the `#<Class:self>` surrogate, where a
# `def` retagged as a class method of the surrogate IS an instance method of
# `Foo.singleton_class.singleton_class`, which is where ruby puts it.
#
# lita spells the corpus's whole cluster this way -- 565 rows behind one file --
# and its method is `private`, called by the DSL beside it.
class Authorization
  def self.plain = :plain

  class << self
    class << self
      private

      def define_deprecated(name)
        define_method(name) { "deprecated:#{name}" }
      end
    end

    define_deprecated :add_user
    define_deprecated :remove_user
  end
end

# An ordinary `class` written inside a singleton body ENDS the run: its own
# `class << self` is its own singleton, not the surrogate's.
class Outer
  class << self
    class Inner
      class << self
        def who = :inners_class_method
      end
    end
    # `Inner` by bare name -- it belongs to the singleton class, which is
    # this method's lexical home, so the bare read resolves while
    # `Outer::Inner` raises.
    def outer_side = Inner.who
  end
end
p Outer.outer_side
p Outer.singleton_class.singleton_class.method_defined?(:who)

