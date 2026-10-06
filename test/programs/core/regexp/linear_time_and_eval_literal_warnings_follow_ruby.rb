# Regexp.linear_time? is false for a capture inside a lookahead, and a
# regexp literal in an eval warns at its own file and line. A failed
# pattern prints its warnings before the error.
p [/a/, /(a)\1/, /(?=(a))/, /(?!(a))/, /(?<=(a))b/, /(?=a)(b)/, /(?<n>a)/, /(?=(?:a))/].map { |re| Regexp.linear_time?(re) }
$VERBOSE = true
eval('/\A[[:alpha\:]]\z/', binding, "pattern.rb", 7)
eval("x = 1\n/\\A[[:^alpha:]0]\\z/", binding, "two.rb", 1)
# A pattern that fails still prints the warnings the parser gave first.
begin
  Regexp.new("[[:alpha:")
rescue RegexpError => e
  p [e.class, e.message]
end
