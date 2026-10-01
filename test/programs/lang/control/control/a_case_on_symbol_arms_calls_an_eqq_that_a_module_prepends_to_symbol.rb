# A module that Symbol prepends with its own `===` comes before
# Symbol#=== in the lookup. After the prepend, a `case` on symbol arms
# calls it for each `when` value, and it can call `super`.
def size_word(x)
  case x
  when :small then "s"
  when :large then "l"
  end
end

p size_word(:small), size_word("small")

module Loose
  def ===(other)
    super || (other.is_a?(String) && to_s == other)
  end
end
Symbol.prepend(Loose)

p size_word(:small), size_word("small"), size_word("large"), size_word("medium")
