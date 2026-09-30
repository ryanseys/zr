# A class that defines a nil-returning `#to_s` is in the program. `gsub`/`sub`
# WITH A BLOCK on a widened (poly) receiver still answers a String, as the
# two-argument blockless form does.

class Poison
  def to_s
    @never_set
  end
end

def escape(text)
  text.to_s.gsub(/[&<>]/) { |c| c == "<" ? "&lt;" : "&gt;" }
end

def first_vowel(text)
  text.to_s.sub(/[aeiou]/) { |c| c.upcase }
end

puts escape("a<b")        # a&lt;b
puts escape(123)          # 123
puts first_vowel("hello") # hEllo
puts first_vowel(42)      # 42

# The blockless, two-argument form already worked before this fix; keep it
# exercised here so a future change can't silently narrow the new rule.
h = { stream: "abc/def", count: 5 }
puts h[:stream].gsub(/[^a-z]/, "_") # abc_def

# The receiver can be poly WITHOUT a `.to_s` in front of it, and then the block
# parameter widens to poly too. gsub/sub always yield the matched substring, a
# String whatever the receiver's static type is, so the parameter is typed that
# way for a boxed receiver as well -- otherwise the slot is declared sp_RbVal
# while the emitter assigns it the raw substring.
def upcase_a(x)
  x.gsub(/a/) { |c| c.upcase }
end

def bracket_vowel(x)
  x.sub(/[aeiou]/) { |c| "[#{c}]" }
end

p upcase_a(true ? "banana" : [1, 2])
p bracket_vowel(true ? "banana" : 5)
