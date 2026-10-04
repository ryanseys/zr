# A string that eval runs sees its calling frame as ruby's does: a
# `return` leaves the frame's method, `$~` and `$_` are the frame's,
# `super` and `defined?(super)` belong to the frame's method, and
# `Module.nesting`, `binding` and `__dir__` answer for the string.

def early
  eval("return :early")
  :late
end
p early

def matched
  "ab" =~ /(b)/
  eval("[$~[0], $1, $`]")
end
p matched

def sets_match
  eval("'cd' =~ /(d)/")
  [$~[0], $1]
end
p sets_match

p eval("'abc'.gsub(/(b)/) { $1.upcase }")
p eval("case 'hello' when /l+/ then $~[0] end")
p eval("[/a/.frozen?, 2.times.map { /a/ }.uniq.size]")
p eval('[1, 2].map { |i| /a#{i}/o.source }')

def own_match = eval("def inner = ('q' =~ /q/; $~[0]); 'r' =~ /r/; [inner, $~[0]]")
p own_match

class Base
  def greet(name) = "hi #{name}"
end

class Child < Base
  def greet(name) = eval("super") + "!"
  def probe = eval("defined?(super)")
end
p Child.new.greet("bo")
p Child.new.probe

module Outer
  class Inner
    p eval("Module.nesting")
  end
end

x = 2
p eval("y = 1; b = binding; [b.local_variable_get(:y), b.local_variable_get(:x)]")
p eval("__dir__")
p eval("__dir__", binding, "/tmp/somewhere/file.rb")
p((eval("super") rescue $!.class))
