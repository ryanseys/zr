"hello world" =~ /(w)(o)(r)/
p $~, $&, $`, $', $+
p $1, $2, $3, $4
if "abc".match?(/b/)
  "abc" =~ /(b)/
  p $1
end
def last_group(s)
  s =~ /(a)(b)?/
  [$1, $2, $+]
end
p last_group("ab"), last_group("a")
