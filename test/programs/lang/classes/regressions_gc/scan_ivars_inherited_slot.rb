# A child class writes to an ivar that the parent also writes. The
# object has one `@v`, and a read gives the last value written.

class T_scan_ivars_inherited_slot_Parent
  def initialize
    @v = 0
    @v = "s"     # parent writes an Integer, then a String
  end
end

class T_scan_ivars_inherited_slot_Child < T_scan_ivars_inherited_slot_Parent
  def initialize
    super
    @v = 42      # child writes the same ivar
  end
  def read
    @v
  end
end

puts T_scan_ivars_inherited_slot_Child.new.read     # 42
