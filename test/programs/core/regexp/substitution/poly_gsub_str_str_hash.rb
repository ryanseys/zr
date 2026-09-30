# `s.gsub(regex, hash)` on a poly-typed receiver uses the hash for
# the replacements, as it does on a String receiver.
#
# The test passes a poly value into a method whose param widens to
# poly.

class A
  attr_accessor :body
  def initialize; @body = "a&b<c>"; end
end
class B
  attr_accessor :body
  def initialize; @body = 42; end
end

def pick(n)
  n > 0 ? A.new : B.new
end

ESCAPES = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;" }.freeze
PATTERN = /[&<>]/.freeze

# `s` here is sp_RbVal because the caller passes
# `src.body` which is poly (A#body is String, B#body is Int).
def html_escape(s)
  s.gsub(PATTERN, ESCAPES)
end

src = pick(1)
puts html_escape(src.body)
