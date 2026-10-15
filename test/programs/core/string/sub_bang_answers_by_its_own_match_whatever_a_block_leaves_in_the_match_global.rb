# sub! and gsub! answer the receiver when their own pattern matched, even
# when the replacement is the matched text, and nil when it did not. A
# block that runs a sub! of its own that matches nothing leaves `$~` nil,
# which does not change that answer.
y = +"zz"
x = +"ab"
p x.sub!(/b/) { y.gsub!(/q/, "-") ? "a" : "b" }, $~
p x.sub!("a") { y.sub!("q") { "-" } ? "b" : "a" }, $~
p x.gsub!(/[ab]/) { y.sub!("q", "-") ? "?" : $& }, $~
p x.gsub!("b") { "zz" =~ /q/; "b" }, $~
p x.sub!("q") { "never" }, $~
p x.gsub!(/q/) { "never" }, $~
p x.sub!("a", "a"), x.gsub!("b", "b"), x
s = +"zz"
t = s
p s.sub!("z") { y.sub!("q", "-") ? "y" : "z" }
p s.gsub!(/z/) { y.gsub!(/q/, "-") ? "y" : "z" }, t
