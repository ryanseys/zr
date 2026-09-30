# `super` in a method define_method made, reached under an alias, looks
# up the name the method was defined under, as a def reached under an
# alias does; `defined?(super)` answers for that name too.
class Base
  def greet(x) = "base #{x}"
  def plain(x) = "plain #{x}"
end

class Kid < Base
  define_method(:greet) { |x| ["kid", defined?(super), super(x)] }
  def plain(x) = ["kid", defined?(super), super]
  alias_method :greet2, :greet
  alias_method :plain2, :plain
end

k = Kid.new
p k.greet(1), k.greet2(2)
p k.plain(1), k.plain2(2)

