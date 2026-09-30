# frozen_string_literal: true
# Bundled tests:
#   - str_setbyte_frozen_literal
#   - strip_nullable_int_cast


# With `# frozen_string_literal: true`, every string literal is
# frozen, and mutation needs a new String (`.dup`, `+`, etc.).
# setbyte on a literal raises FrozenError with the CRuby message.

# Direct literal recv.
begin
  "abc".setbyte(0, 67)
  puts "no raise (literal)"
rescue FrozenError => e
  puts "literal: " + e.message
end

# LV pointing at a literal.
s = "abc"
begin
  s.setbyte(0, 67)
  puts "no raise (lv-literal): " + s
rescue FrozenError => e
  puts "lv-literal: " + e.message
end

# A dup'd string can change.
s2 = "abc".dup
s2.setbyte(0, 67)
puts s2   # Cbc

# Concatenation produces a new String too.
s3 = "x" + "y"
s3.setbyte(0, 90)
puts s3   # Zy

# Aliasing: setbyte on a shared object affects both refs.
s4 = "ab".dup
s5 = s4
s4.setbyte(0, 67)
puts s5   # Cb (shared object, both see the mutation)

# ivar holding a dup'd string changes through a method call.
class T_str_setbyte_frozen_literal_Buf
  attr_reader :s
  def initialize
    @s = "abc".dup
  end
  def hit
    @s.setbyte(0, 67)
  end
end
b = T_str_setbyte_frozen_literal_Buf.new
b.hit
puts b.s   # Cbc
