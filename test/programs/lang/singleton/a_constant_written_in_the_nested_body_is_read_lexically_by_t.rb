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

# A constant written in the nested body is read lexically by the `def` beside
# it, and `RESULT` -- a constant whose value the statement order decides --
# sees the method the nested body just defined. (WHERE the constant lives is
# the one-level-deeper form of zr's existing singleton-constant divergence;
# see tests/gaps/a_nested_singleton_bodys_constant_is_hoisted.rb.)
class WithConst
  class << self
    class << self
      SUFFIX = "!"
      def shout(s) = s + SUFFIX
    end
    RESULT = shout("hi")
  end
end
p WithConst.singleton_class::RESULT

