# sub and gsub convert a replacement that was given, nil too; scan converts
# its pattern once and leaves the last match in $~; match calls the
# pattern's own match.
$stderr = $stdout
p(("hello".sub(Object.new, nil) rescue $!.class))
p(("hello".sub(Object.new, "x") rescue $!.class))
p(("hello".gsub(/[aeiou]/, []) rescue $!.class), ("hello".gsub(/[aeiou]/, nil) rescue $!.class), ("hello".gsub(/[aeiou]/, Object.new) rescue $!.class))
o = Object.new
def o.to_str = (($n ||= 0); $n += 1; "o")
p "o_o".scan(o), $n
r = /./.dup
def r.match(*) = :foo
p "hello".match(r)
"hello" =~ /ll/
"hello".scan(/l/) { "ok" =~ /ok/ }
p $~[0]
p "hello".scan(/l/) { |x| x }
