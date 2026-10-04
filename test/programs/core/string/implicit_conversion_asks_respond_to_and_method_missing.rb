# An implicit to_str or to_int conversion goes through a program's
# respond_to? and method_missing, as rb_check_funcall does.
$stderr = $stdout
obj = Object.new
def obj.respond_to?(arg, *) = true
def obj.method_missing(*args) = "o"
p "hello".rindex(obj), "hello".index(obj), "hello".include?(obj), "a" + obj
n = Object.new
def n.respond_to?(arg, *) = true
def n.method_missing(*args) = 2
p Integer(n), [1, 2, 3].first(n)
o = Object.new; def o.to_str = "o"
i = Object.new; def i.to_int = 2
p "hello".rindex(o), "hello".rindex("l", i), "hello".rindex(/l/, i)
p "hello".byterindex(o), "hello".byterindex("l", i), "hello".byterindex(/l/, i)
s = +"hello"; p s.slice!(i), s
s = +"hello"; p s.slice!(i, i), s
s = +"hello"; p s.slice!(i..i), s
p (("a" << -1) rescue $!.class), (("a".dup.concat(-1)) rescue $!.class)
