# Regexp reflection/class-method surface
# casefold?, option constants, last_match, try_convert, options, ~, timeout,
# union, new(re)
p(/abc/i.casefold?)
p(/abc/.casefold?)
p(Regexp::IGNORECASE)
p(Regexp::EXTENDED)
p(Regexp::MULTILINE)
p(/abc/.options)
p(/abc/i.options)
p(/abc/m.options)
"abc" =~ /b/
p(Regexp.last_match)
p(Regexp.last_match(0))
p(Regexp.try_convert(/x/))
p(Regexp.try_convert("x"))
p(Regexp.new("ab").options)
p(/re/.timeout)
p(Regexp.timeout)
r = Regexp.new(/ab/i)
p(r.source)
p(r.casefold?)
arr = [/foo/, /bar/]
p(Regexp.union(arr))
p(Regexp.union(/foo/i, /bar/).match?("FOO"))
$_ = "hello world"
p(~/world/)
p(~/xyz/)
