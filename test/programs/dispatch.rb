# native only
def show(label)
  answer = yield.inspect rescue "#{$!.class}: #{$!.message}"
  puts("#{label}: #{answer.gsub(/0x\h+/, "0xXX")}")
end

class Base; def who = "Base"; end
class Sub < Base; end
o = Sub.new
show("plain") { o.who }

# a definition on the superclass after the answer was cached
class Base; def who = "Base2"; end
show("redefined super") { o.who }

# a definition on the subclass shadows it
class Sub; def who = "Sub"; end
show("shadowed") { o.who }
show("super from sub") { Sub.new.method(:who).super_method.call }

# remove_method uncovers the inherited one
class Sub; remove_method :who; end
show("removed") { o.who }

# undef_method hides it entirely
class Sub; undef_method :who; end
show("undefd") { o.who }
class Sub; def who = "Sub again"; end
show("redefined after undef") { o.who }

# include after the fact
module M; def who = "M"; def only_m = "only_m"; end
class Late; end
l = Late.new
show("before include") { l.only_m }
class Late; include M; end
show("after include") { l.only_m }

# prepend wins over the class's own
module P; def who = "P(#{super})"; end
class Pre; def who = "Pre"; end
pr = Pre.new
show("before prepend") { pr.who }
class Pre; prepend P; end
show("after prepend") { pr.who }

# extend adds to one object only
module E; def only_e = "only_e"; end
a = Object.new
b = Object.new
a.extend(E)
show("extended") { a.only_e }
show("not extended") { b.only_e }

# a singleton def
def b.solo = "solo"
show("singleton") { b.solo }
show("singleton on other") { a.solo }

# alias keeps the body the name had
class Al; def one = 1; alias_method :two, :one; def one = 11; end
show("alias body") { [Al.new.one, Al.new.two] }

# visibility
class Vis; def hidden = "h"; end
v = Vis.new
show("public") { v.hidden }
class Vis; private :hidden; end
show("private") { v.hidden }
class Vis; public :hidden; end
show("public again") { v.hidden }

# method_missing and respond_to_missing?
class MM
  def respond_to_missing?(n, _ = false) = n == :ghost
  def method_missing(n, *a) = n == :ghost ? "ghost" : super
end
m = MM.new
show("respond_to") { m.respond_to?(:ghost) }
show("ghost") { m.ghost }
show("no ghost") { m.other }

# Class.new with a runtime superclass
k = Class.new(Base) { def who = "anon" }
show("anon") { k.new.who }

# a module included into a module already included elsewhere
module Inner; def deep = "deep"; end
module Outer; end
class Host; include Outer; end
h = Host.new
show("before nested") { h.deep }
module Outer; include Inner; end
show("after nested") { h.deep }

# dup and clone carry their own tables
class Orig; def tag = "orig"; end
Copy = Orig.dup
class Copy; def tag = "copy"; end
show("dup split") { [Orig.new.tag, Copy.new.tag] }

# define_method and remove through the reflection API
class Dyn; end
Dyn.define_method(:made) { "made" }
show("define_method") { Dyn.new.made }
Dyn.send(:remove_method, :made)
show("removed dynamic") { Dyn.new.made }

# a conversion probe: the negative answer must not stick
class Conv; end
c = Conv.new
show("no to_str") { "x" + c }
class Conv; def to_str = "converted"; end
show("to_str now") { "x" + c }

# ancestors and instance_methods stay in ruby's order
show("ancestors") { Pre.ancestors.first(3).map(&:to_s) }
show("methods") { Al.instance_methods(false).sort }
