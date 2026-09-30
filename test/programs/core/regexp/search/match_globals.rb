# frozen_string_literal: true

# `$~` and the family that reads through it. All of them come off one
# last-match slot, which is FRAME-LOCAL: a method that matches and
# returns leaves the caller's `$1` alone.

if "hello world" =~ /(\w+)\s(\w+)/
  p $1, $2, $3
  p $~.class, $~[0], $~[2]
  p $&, $`, $', $+
end

# A miss clears the slot rather than leaving the last hit behind.
p("abc" =~ /z/)
p $~, $1, $&

# The numbers reach past nine, and a group the pattern never declared
# is nil rather than an error.
p("abcdefghijk" =~ /(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)/)
p $10, $11

# `$+` is the highest group that PARTICIPATED, skipping one that was
# declared but did not match.
p("ab" =~ /(a)(b)|(z)/)
p $+, $3

module Parse
  def self.number(text)
    text =~ /(\d+)/ ? $1.to_i : nil
  end
end

# The method's own match does not reach here.
"outer" =~ /(outer)/
p Parse.number("x42y"), $1
p Parse.number("none"), $1

# A block shares the method's slot, and the method's stays its own.
def scanned(list)
  list.map do |word|
    word =~ /(\w)$/
    $1
  end
end
p scanned(%w[one two]), $1

# A class body is its own scope too.
class Opened
  "class" =~ /(c)/
  p $1
end
p $1

# `=~` with a named pattern on the LEFT binds each name to a local.
if /(?<year>\d{4})-(?<month>\d{2})/ =~ "2026-09"
  p year, month
end

# A miss leaves the names nil rather than raising.
/(?<absent>\d)/ =~ "no digits"
p absent

# `MatchData` answers the same groups the globals do.
found = /(?<a>\w)(?<b>\w)/.match("xy")
p found[:a], found[:b], found.captures, found.named_captures, found.pre_match

# `defined?` reads the slot without disturbing it.
p defined?($~), defined?($1), defined?($&)
"z" =~ /(z)/
p defined?($~), defined?($1), defined?($2), defined?($&), $1
