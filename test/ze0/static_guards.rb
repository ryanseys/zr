# frozen_string_literal: true

# A guard a whole-program compile can decide leaves only the branch that
# runs. It matters more than it saves: a `def` in each branch of a guard
# that stayed dynamic would leave TWO definitions of one name and the
# later one would simply win, so an engine gate would pick the branch
# written for the engine this is not.

if RUBY_ENGINE == "truffleruby"
  class Fast
    def kind = :truffle
  end
else
  class Fast
    def kind = :ruby
  end
end

p Fast.new.kind

def report
  if RUBY_ENGINE != "ruby"
    :other
  else
    :ruby
  end
end
p report

p(RUBY_VERSION >= "3.3.0" ? :new : :old)

# `&&`, `||` and `!` fold three-valued, so one decided side settles the
# guard even when the other stays unknown.
p :yes if RUBY_ENGINE == "ruby" && !(RUBY_ENGINE == "jruby")
p(:no) unless RUBY_ENGINE == "opal" || RUBY_ENGINE == "rbx"

# The anchored `::Foo` means the TOP LEVEL, not an empty namespace.
module Wrapper
  Integer = :shadowed

  def self.plain = ::Integer
  def self.shadowed = Integer
end

p Wrapper.plain, Wrapper.shadowed
p ::Wrapper.plain
__END__
:ruby
:ruby
:new
:yes
:no
Integer
:shadowed
Integer
