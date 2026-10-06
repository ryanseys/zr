if ARGV.size > 5
  alias $pre $`
end
p $pre
def link = (alias $whole $&)
link
"xaby" =~ /ab/
p [$whole, $pre]
if true
  alias $post $'
end
"xaby" =~ /ab/
p $post
