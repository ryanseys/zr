# !0 / !:foo are false in Ruby (only nil/false are falsy), so 0
# is truthy.
puts !!0
puts !!:foo
puts !!""
puts !nil
puts !false
puts !true
puts !"hello"
