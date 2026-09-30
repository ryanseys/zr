# Class ivars and class variables, which live in tables of their own.



b = Ruby::Box.new
b.eval("class Array; @civ = 7; def self.civ = @civ; end")
b.eval("class Array; @@cv = 3; def self.cv = @@cv; end")
p(begin; Array.civ; rescue NoMethodError; :nome; end)
p b.eval("Array.civ")
p b.eval("Array.cv")
