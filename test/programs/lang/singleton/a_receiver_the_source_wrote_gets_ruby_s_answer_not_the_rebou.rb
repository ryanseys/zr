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

# A receiver the SOURCE wrote gets ruby's answer, not the rebound form's --
# only the rebound `self.singleton_class` zr synthesizes for a receiverless
# call is exempt. (The message names the surrogate a module where ruby names
# it a class -- see tests/gaps/a_singleton_class_surrogate_is_a_module.rb.)
begin
  Authorization.singleton_class.define_deprecated(:nope)
rescue NoMethodError => e
  p e.class
end

