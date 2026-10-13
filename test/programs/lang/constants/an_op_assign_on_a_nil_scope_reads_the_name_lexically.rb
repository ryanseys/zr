# `scope::Name op= value` and `scope::Name &&= value` read Name with
# getconstant's allow_nil: a nil scope reads Name lexically, as a bare
# Name would, and only the write then refuses the nil scope. `||=`, a
# plain read and a plain write refuse the nil scope at once.
$stdout.sync = true
def try(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

n = nil
try("op-assign unset") { n::NotDefinedHere += 1 }
try("op-assign set") { n::String += "x" }
try("op-assign Integer") { n::Integer += 1 }
try("and-assign unset") { n::NotDefinedHere &&= 1 }
try("and-assign set") { n::String &&= 1 }
try("or-assign") { n::String ||= 1 }
try("read") { n::String }
try("write") { n::Q = 1 }

module Outer
  Inner = 5
  def self.bump(scope)
    scope::Inner += 1
  end

  def self.both(scope)
    scope::Inner &&= 7
  end
end
try("lexical in a module") { Outer.bump(nil) }
try("and lexical in a module") { Outer.both(nil) }
try("real scope") { Outer.bump(Outer) }
p Outer::Inner
class KScope
  V = 1
end
k = KScope
try("a class scope") { k::V += 1 }
p k::V
try("a non-module scope") { 1::V += 1 }
try("a string scope") { "s"::V &&= 1 }

# The same in code that eval compiles.
try("eval op-assign unset") { eval("n::NotDefinedHere += 1") }
try("eval op-assign set") { eval("n::String += 'x'") }
try("eval and-assign unset") { eval("n::NotDefinedHere &&= 1") }
try("eval or-assign") { eval("n::String ||= 1") }
