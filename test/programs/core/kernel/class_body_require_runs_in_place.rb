# A `require` written in a `class`/`module` BODY runs AT ITS OWN POSITION in
# CRuby, at the top-level cref -- not after the whole enclosing file.
#
# So `module M; puts "before"; require_relative "x"; puts "after"; end`
# prints before, then the output of x, then after. The constants that x
# defines go to Object, not to M.
#
# A required FFI vocabulary is also visible to the statements below the
# `require` (see the ffi test "module body require declares before the next
# statement").
module M
  puts "before"
  require_relative "class_body_require/inner"
  puts "after"
  p INNER_TOP
  p InnerClass.hi
end

# The constant went to Object, not to M.
p M.constants
p Object.const_defined?(:INNER_TOP)
p defined?(M::INNER_TOP)

# A second require of the same file is a no-op, and answers false.
module N
  p require_relative("class_body_require/inner")
end
puts "done"
