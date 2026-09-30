# Statement-form `@x OP= v` for the bitwise / shift / multiplicative
# operators. Each one changes the ivar, so `@a &= 0x80` sets @a to
# 128. Walks each operator that has an `OP=` form.

class T_ivar_op_assign_bitwise_and_shift_C
  attr_reader :a
  def initialize; @a = 0xff; end
  def m_amp; @a &= 0x80; end
  def m_or;  @a |= 0x01; end
  def m_xor; @a ^= 0xff; end
  def m_lsh; @a <<= 1; end
  def m_rsh; @a >>= 1; end
  def m_mul; @a *= 2; end
end

c = T_ivar_op_assign_bitwise_and_shift_C.new; c.m_amp; puts "amp: #{c.a}"
c = T_ivar_op_assign_bitwise_and_shift_C.new; c.m_or;  puts "or: #{c.a}"
c = T_ivar_op_assign_bitwise_and_shift_C.new; c.m_xor; puts "xor: #{c.a}"
c = T_ivar_op_assign_bitwise_and_shift_C.new; c.m_lsh; puts "lsh: #{c.a}"
c = T_ivar_op_assign_bitwise_and_shift_C.new; c.m_rsh; puts "rsh: #{c.a}"
c = T_ivar_op_assign_bitwise_and_shift_C.new; c.m_mul; puts "mul: #{c.a}"
