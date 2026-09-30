# `Regexp.new("literal")` / `Regexp.compile("literal")` with a
# string-literal argument matches like a `/literal/` regex literal,
# also through a local or a constant that holds it.

# Direct call on the constructor expression.
puts Regexp.new("foo").match?("foobar")   # true
puts Regexp.new("xyz").match?("foobar")   # false

# Local variable bound to a Regexp.new result.
pat = Regexp.new("\\d+")
puts pat.match?("hello 42")                # true
puts pat =~ "abc 123"                      # 4

# Compile alias.
pat2 = Regexp.compile("foo")
puts pat2.match?("foobar")                 # true

# Constant bound to a Regexp.new result.
RE = Regexp.new("foo")
puts RE.match?("foobar")                   # true
puts "abc foo def" =~ RE                   # 4

# Dynamic-arg form: the argument is built at runtime via interpolation.
tag = "div"
puts Regexp.new("<#{tag}").match?("<div>")  # true
puts Regexp.new("<#{tag}").match?("<span>") # false

# Local bound to a dynamic Regexp.new: it keeps the pattern built from
# `tag`.
pat_dyn = Regexp.new("<#{tag}>")
puts pat_dyn.match?("<div>")                # true
puts pat_dyn =~ "before <div> after"        # 7

# Dyn arg from method parameters -- the common idiom for an
# assert_select-style helper.
def find_tag(body, tag)
  re = Regexp.new("<#{tag}[^>]*>")
  body =~ re
end
puts find_tag("foo <span class=\"y\"> bar", "span") # 4

# Regexp.escape neutralizes regex metachars so the resulting
# string matches the original bytes literally inside `Regexp.new`.
puts Regexp.escape("foo+bar")              # foo\+bar
puts Regexp.escape("a.b*c")                # a\.b\*c
content = "foo.bar"
literal_pat = Regexp.new(Regexp.escape(content))
puts literal_pat.match?("foo.bar")         # true
puts literal_pat.match?("fooXbar")         # false (the . is now literal)

# `=~` returns Integer|nil matching CRuby (not -1 for no-match).
puts ("abc" =~ /b/).inspect                # 1
puts ("abc" =~ /xyz/).inspect              # nil
puts ("abc" =~ /xyz/).nil?                 # true
puts ("abc" =~ /b/).nil?                   # false

# $~ / $& / $` / $' -- regex match globals. $~ is a real MatchData
# (its to_s is the whole match, so `puts $~` prints like $&).
"hello world" =~ /(o w)/
puts $~                                    # o w
puts $&                                    # o w
puts $`                                    # hell
puts $'                                    # orld
