# `class X < Module` -- a module FACTORY, whose instances are real modules.
#
# This is NOT the value-subclass payload shape and must not become it: a
# wrapper holding a module is not a module, so it would fail `include`,
# `Module#===`, constant lookup and `ancestors`. Instead `X.new` mints a real
# runtime module id and tags it as belonging to X, so only the question "what
# is your class?" changes answer.
#
# 22 of the gem corpus's `Module` rows come from ONE file --
# `activesupport/lib/active_support/deprecation/proxy_wrappers.rb` -- which
# gates actioncable, actionmailer, actionview, activejob, activemodel,
# activerecord, activestorage and the rest of the Rails stack.

class LazilyDefineAttributes < Module
  def initialize(attributes)
    @attributes = attributes
  end

  def included(base)
    base.instance_variable_set(:@lazy, @attributes)
  end

  def attributes
    @attributes
  end
end

m = LazilyDefineAttributes.new([:a, :b])

# Its class is the subclass, and it is a module all the same.

# A user instance method runs against it, and ivars persist across calls --
# `initialize` wrote `@attributes`, `attributes` reads it back.
p m.attributes

