# frozen_string_literal: true

# A `class` or `module` naming one the runtime always carries REOPENS it.
# The id is the backend's, so no row is minted beside it: the body runs
# as a `class_eval` on the constant, and its `def`s install where they
# stand.

class Object
  def tagged = :tagged
end

class String
  def twice = self * 2
end

class Hash
  def shout = "#{size} pairs!"
end

module Enumerable
  def second = to_a[1]
end

class Integer
  def double = self * 2
end

p 1.tagged, :s.tagged
p "ab".twice
p({ a: 1 }.shout)
p [1, 2, 3].second
p 21.double

# The reopen adds to the class; the native half is still there.
p "ab".upcase, [1, 2].sum, ({ a: 1 }).keys

# A `def` the reopen writes is a real method row on the builtin.
p String.instance_method(:twice).owner
p String.method_defined?(:twice)

# A class written in a scope the RUNTIME owns takes the scope as it is
# spelled, which is the fully-qualified name `Class.name` answers.
require "digest"

class Digest::Extra
  def go = :extra
end

p Digest::Extra.new.go
p Digest::Extra.name

# A `class << obj` body reaches the object's singleton class, so a macro
# written there names one of its methods.
module Registry
  class << self
    attr_accessor :tags
    alias labels tags
  end
end

Registry.tags = { a: 1 }
p Registry.tags, Registry.labels
__END__
:tagged
:tagged
"abab"
"1 pairs!"
2
42
"AB"
3
[:a]
String
true
:extra
"Digest::Extra"
{a: 1}
{a: 1}
