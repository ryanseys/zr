# A constructor body with a local Array (`arr`), in a small class
# defined after another class. Each call gives the right value, and
# many calls do not use up the GC roots.

class T_value_type_ctor_gc_save_Foo
  def make
    [1, 2, 3]
  end
end

class T_value_type_ctor_gc_save_Vec
  attr_reader :sum
  def initialize(x, y)
    arr = [x, y, x + y]
    @sum = arr[2]
  end
end

f = T_value_type_ctor_gc_save_Foo.new
puts f.make.length            # 3
v = T_value_type_ctor_gc_save_Vec.new(3, 4)
puts v.sum                    # 7

# Many constructor calls.
sum = 0
i = 0
while i < 200
  vv = T_value_type_ctor_gc_save_Vec.new(i, i + 1)
  sum = sum + vv.sum
  i = i + 1
end
puts sum                       # 200 * (i + (i+1)) summed = sum of (2i+1) for i=0..199 = 200*200 = 40000
