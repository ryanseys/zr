# An object whose ivars moved out of its cell gets them back there when
# remove_instance_variable leaves few enough, as CRuby's fields embed
# again (test_object.rb, test_remove_instance_variable_re_embed).
require "objspace"
c = Class.new { def initialize; @v0 = @v1 = @v2 = nil; end }
o = c.new
3.times { |i| o.instance_variable_set(:"@v#{i}", i) }
p ObjectSpace.dump(o).include?('"embedded":true')
o.instance_variable_set(:@overflow, 99)
p ObjectSpace.dump(o).include?('"embedded":true')
o.remove_instance_variable(:@overflow)
p ObjectSpace.dump(o).include?('"embedded":true')
p (0..2).map { o.instance_variable_get(:"@v#{_1}") }
