# `defined?` answers as CRuby's defined_expr0 does: every write, an
# operator assignment among them, is an "assignment"; `it` is a local;
# a call with a block literal is an expression; `$1` and `$&` are
# defined while the last match holds them; `$~` always is.
a = nil
@x = 1
p defined?(a ||= 1), defined?(a &&= 2), defined?(a += 1)
p defined?(@x += 1), defined?(@y ||= 1), defined?($g ||= 2)
p defined?(K ||= 1), defined?(a = 1), defined?(@x.to_s.b = 1)
p [1].map { defined?(it) }
p defined?(p { }), defined?(p)
p defined?($~), defined?($!)
"a" =~ /(a)/
p defined?($1), defined?($2), defined?($&), defined?($`)
"zz" =~ /nomatch/
p defined?($1), defined?($&)

__END__
"assignment"
"assignment"
"assignment"
"assignment"
"assignment"
"assignment"
"assignment"
"assignment"
nil
["local-variable"]
"expression"
"method"
"global-variable"
"global-variable"
"global-variable"
nil
"global-variable"
"global-variable"
nil
nil
