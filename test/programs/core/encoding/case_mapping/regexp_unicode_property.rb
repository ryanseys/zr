# `\p{...}` character properties. A program can use them in a regexp, and
# the author has no other way to write the same test.
#
# General category is a partition: each character has one category, and
# `\p{Lu}` and `\p{L}` both match an upper-case letter. The emoji properties
# overlap. The POSIX-named properties also fold case under /i.

# The shape this arrived as: once-campfire's String#all_emoji?, verbatim.
class String
  def all_emoji?
    self.match?(/\A(\p{Emoji_Presentation}|\p{Extended_Pictographic}|️)+\z/u)
  end
end

p "🔔".all_emoji?
p "🔔🎉".all_emoji?
p "hi".all_emoji?
p "🔔x".all_emoji?

# \p{Word}, which rails_autolink uses to trim trailing punctuation.
p "see http://x.test/a." .sub(/[^\p{Word}\/]+\z/, "")
p "abc_123".scan(/\p{Word}/).join

s = "Aa1 _-€é́あ🔔"

# Two-letter categories, and the one-letter form that stands for all of them.
p s.scan(/\p{Lu}/)
p s.scan(/\p{Ll}/).join
p s.scan(/\p{L}/).join
p s.scan(/\p{Nd}/)
p s.scan(/\p{Pc}/) + s.scan(/\p{Pd}/)
p s.scan(/\p{P}/)
p s.scan(/\p{Sc}/)
p s.scan(/\p{Zs}/)
p s.scan(/\p{Mn}/).length

# Negated, both spellings.
p s.scan(/\P{L}/).length
p s.scan(/[^\p{L}]/).length

# Inside a class, mixed with literals and POSIX brackets.
p s.scan(/[\p{Lu}\p{Nd}_]/)
p s.scan(/[\p{Alpha}[:digit:]]/).join
p s.scan(/[^\p{L}\p{N}]/).length
p s.scan(/[\P{L}]/).length

# The name is matched the way CRuby matches it: case, underscores, hyphens and
# spaces are all the same name.
p "é".match?(/\p{alpha}/)
p "É".match?(/\p{Upper}/)
p "🔔".match?(/\p{extended pictographic}/)
p "🔔".match?(/\p{EXTENDED_PICTOGRAPHIC}/)
p "🔔".match?(/\p{Extended-Pictographic}/)

# A POSIX-named property folds under /i exactly as its bracket does; a
# category does not, because the category IS the case distinction.
p "É".match?(/\p{Lower}/i)
p "É".match?(/[[:lower:]]/i)
p "É".match?(/\p{Ll}/)

# Quantified, anchored, alternated, and inside a group.
p "Hello".match?(/\A\p{Lu}\p{Ll}+\z/)
p "hello".match?(/\A\p{Lu}\p{Ll}+\z/)
p "a1".match?(/\A(\p{L}|\p{N})+\z/)
p "Wörld! 123".gsub(/\p{L}+/) { |w| w.upcase }
