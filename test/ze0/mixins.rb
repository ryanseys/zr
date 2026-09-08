# frozen_string_literal: true

# `include`, `extend` and `prepend` are ordinary sends to the class the
# body is running on. ze0 registers a class statically, but nothing about
# a mixin is static: the runtime answers where a method lands and what
# `ancestors` reports.

module Loud
  def speak(word) = "#{super(word)}!"
end

module Greeter
  def hello = "hello from #{name}"
end

module Tools
  def helper = :helped

  extend self
end

class Quiet
  def speak(word) = word
end

class Shouter < Quiet
  include Loud
  extend Greeter

  def own = :own
end

class Front
  prepend Loud

  def speak(word) = word.upcase
end

p Shouter.new.speak("hi")
p Shouter.hello
p Shouter.new.own
p Shouter.ancestors.take(3).map(&:to_s)
p Shouter.include?(Loud)
p Front.new.speak("hi")
p Front.ancestors.take(2).map(&:to_s)
p Tools.helper
p Tools.singleton_class.ancestors.take(2).map(&:to_s)

# A module can be mixed into more than one class, and each keeps its own
# superclass above it.
class Whisper
  def speak(word) = word.downcase
end

class Murmur < Whisper
  include Loud
end
p Murmur.new.speak("HI")

# An object extends one module without its class changing at all.
class Named
  def name = "one"
end

one = Named.new
one.extend(Greeter)
p one.hello
p Named.new.respond_to?(:hello)
__END__
"hi!"
"hello from Shouter"
:own
["Shouter", "Loud", "Quiet"]
true
"HI!"
["Loud", "Front"]
:helped
["#<Class:Tools>", "Tools"]
"hi!"
"hello from one"
false
