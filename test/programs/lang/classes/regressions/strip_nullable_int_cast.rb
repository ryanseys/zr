# frozen_string_literal: true
# Bundled tests:
#   - str_setbyte_frozen_literal
#   - strip_nullable_int_cast


# A setter-shaped method gets a Foo, then nil, then an Integer (from
# a method that returns an Integer). The ivar takes each value.

class Foo; end
class T_strip_nullable_int_cast_C
  def take(f)
    @f = f
  end
  def get_int; 42; end
end
c = T_strip_nullable_int_cast_C.new
c.take(Foo.new)
c.take(nil)
c.take(c.get_int)
puts "ok"
