# Reopening `Module` and `Class` themselves must work. A class value's
# own ancestry runs `Class -> Module -> Object`, so a method added by
# reopening either one registers correctly, like any other builtin
# reopen.
#
# minitest's spec.rb opens with `class Module; def infect_an_assertion ...`
# and calls it 34 times to build the expectations DSL.
class Module
  def zr_tag = "mod:#{name}"

  def zr_define(sym)
    class_eval "def #{sym}; :#{sym}_ran; end"
  end
end

class Class
  def zr_kind = "class:#{name}"
end

module M; end
class C; end
class D < C; end

# Every module and every class answers the Module reopen...
p M.zr_tag
p C.zr_tag
p String.zr_tag
p Comparable.zr_tag

# ...and only classes answer the Class reopen.
p C.zr_kind
p D.zr_kind
p Integer.zr_kind
p M.respond_to?(:zr_kind)

# A method added to Module is a real instance method of it, so the reflection
# surface agrees.
p Module.instance_method(:zr_tag).owner
p Class.method_defined?(:zr_tag)
p M.is_a?(Module)

# The reopened method doing what minitest's does: defining methods on the
# receiver from a computed string.
C.zr_define(:greet)
p C.new.greet

# A reopen must not displace the builtin surface it sits beside.
p C.name
p D.superclass
p C.instance_methods(false).sort
