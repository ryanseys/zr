# Edge cases of String, format and unpack that answer as ruby's do.
def t
  p yield
rescue => e
  p [e.class, e.message]
end

# sub! and gsub! return the receiver after any match, even when the text
# comes out the same.
t { (+"cats").sub!(/s$/, "s") }
t { (+"cats").gsub!("a", "a") }
t { (+"cats").sub!(/x/, "y") }

# A replacement argument wins over a block.
t { "abc".gsub("b", "X") { "Y" } }
t { "abc".sub(/b/, "X") { "Y" } }

# $~.regexp after a String pattern is a Regexp.
"he[[o".gsub("[", "]")
t { $~.regexp }
"a.b".sub(".", "-")
t { $~.regexp }

# casecmp and casecmp? convert with to_str; a to_str that gives no String
# raises.
class Wrap
  def initialize(s) = @s = s
  def to_str = @s
end
t { "abc".casecmp(Wrap.new("ABD")) }
t { "abc".casecmp?(Wrap.new("ABC")) }
t { "abc".casecmp(5) }
t { "abc".casecmp(Wrap.new(5)) }
t { "abc" <=> Wrap.new(5) }

# Frozen receivers: a valid scrub! answers self; tr! and friends raise
# even when nothing would change.
t { "fine".freeze.scrub! }
t { "AB".freeze.tr!("x", "y") }
t { "AB".freeze.tr_s!("x", "y") }
t { "AB".freeze.delete_prefix!("z") }
t { "AB".freeze.delete_suffix!("z") }

# An explicit nil is no case-mapping option.
t { "ab".upcase(nil) }
t { "AB".downcase(nil) }

# unpack: X* backs over the rest, and an unknown directive is quoted as
# ruby quotes it.
t { "abcd".unpack("CX*C") }
t { "ab".unpack("H\0H") }
t { "ab".unpack("C\u0001C") }
t { "ab".unpack("Cé") }

# RUBY_DESCRIPTION and RUBY_PLATFORM are frozen.
t { [RUBY_DESCRIPTION.frozen?, RUBY_PLATFORM.frozen?] }

# A * width or precision must fit in an int.
t { format("%*s|", 99_999_999_999, "a") }
t { format("%.*s|", 2_147_483_648, "a") }
t { format("%*s|", -2_147_483_649, "a") }
t { format("%*s|", 1e20, "a") }

# A beginless or endless String range cannot tell inclusion.
t { (.."m").include?("a") }
t { ("a"..).include?("b") }
