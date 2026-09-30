# When parent and child both write the same ivar name, the object has
# one `@data`. The GC marks it once and keeps its value alive.
#
# Here parent's `@data` gets an Array or a String, and child also
# writes `@data` from a method that can return different classes.
# The loop below makes GC pressure.

class T_gc_scan_skip_inherited_ivar_Base
  def initialize(kind)
    if kind == 0
      @data = [1, 2, 3]
    else
      @data = "hello"
    end
  end
end

class T_gc_scan_skip_inherited_ivar_Holder
  def initialize(v)
    @v = v
  end
  attr_reader :v
end

class T_gc_scan_skip_inherited_ivar_Child < T_gc_scan_skip_inherited_ivar_Base
  def initialize(h)
    super(0)
    @data = h.v
  end
end

class T_gc_scan_skip_inherited_ivar_Trash
  def initialize(n)
    @n = n
    @s = "padding payload " * 64
  end
end

h_str = T_gc_scan_skip_inherited_ivar_Holder.new("from-holder")
T_gc_scan_skip_inherited_ivar_Holder.new(123)
c = T_gc_scan_skip_inherited_ivar_Child.new(h_str)

junk = []
i = 0
while i < 5000
  junk << T_gc_scan_skip_inherited_ivar_Trash.new(i)
  i = i + 1
end

puts junk.length
puts "ok"
