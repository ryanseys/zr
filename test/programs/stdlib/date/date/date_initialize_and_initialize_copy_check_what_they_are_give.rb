# Date#initialize takes the civil parts, and Date.civil never calls a
# subclass's initialize. initialize_copy takes only another Date, and a
# simple date cannot take the parts of one with a time of day.
require "date"
d = Date.new(2001, 2, 3)
p((d.send(:initialize_copy, 1) rescue $!), (Date.allocate.send(:initialize_copy, DateTime.now).class rescue $!))
p((d.dup.freeze.send(:initialize_copy, Date.new) rescue $!))
c = Class.new(Date) { def initialize(*a) = (p a; super) }
p c.new(2001, 2).to_s, c.civil(2001, 3).to_s, c.new.class == c
p Date.new(2001, 2, 3.5), Date.allocate.send(:initialize, 2000), Date.instance_method(:initialize).arity, DateTime.new(2001).class
p (DateTime.allocate.send(:initialize, 2001, 2, 3) rescue $!)
p d.dup == d, d.clone.frozen?, DateTime.now.dup.class, Date.new(-1, -1, -1), (Date.new(2001, 2, 30) rescue $!), (Date.new("x") rescue $!)
