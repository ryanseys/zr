# Under Warning[:performance], a program that writes over one of the
# core's basic operators -- a def, an alias, define_method, remove_method,
# undef_method or a prepend in front of it -- is told once, with the
# category; a name the interpreter does not answer in place, a class
# outside the table, or the category off, says nothing.
def Warning.warn(message, category: nil) = super("#{category}: #{message}")
Warning[:performance] = true
class Integer
  def +(o) = 1
  def +(o) = 2
end
class String
  alias_method :length, :to_s
end
class Array
  define_method(:empty?) { true }
end
class Hash
  remove_method :size
end
class Float
  undef_method :<
end
module M; def ==(o) = true; end
class Symbol
  prepend M
end
class Object
  def +(o) = 3
end
class Integer
  def times = 0
end
class NilClass
  def nil? = 1
end
Warning[:performance] = false
class Float
  def -(o) = 0
end
puts "done"
