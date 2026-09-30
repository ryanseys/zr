# `@@x op= rhs` works as `@@x = @@x op rhs`. `&&=` on a class variable
# works too.

class T_cvar_op_write_Counter
  @@count = 0
  @@total = 100
  @@flag = 1

  def self.bump
    @@count += 1
    @@total += 10
  end

  def self.shift
    @@count <<= 2
  end

  def self.zero_flag
    @@flag &&= 7
  end

  def self.report
    puts @@count
    puts @@total
    puts @@flag
  end
end

T_cvar_op_write_Counter.bump
T_cvar_op_write_Counter.bump
T_cvar_op_write_Counter.bump
T_cvar_op_write_Counter.report     # 3, 130, 1

T_cvar_op_write_Counter.shift
T_cvar_op_write_Counter.report     # 12, 130, 1

T_cvar_op_write_Counter.zero_flag  # @@flag is truthy (1), so &&= writes 7
T_cvar_op_write_Counter.report     # 12, 130, 7
