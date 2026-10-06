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

p Authorization.add_user
p Authorization.remove_user
p Authorization.plain

