class T_gc_save_double_in_new_GcSaveDoubleInNew
  def initialize(path)
    data = [1, 2, 3]
    @x = data
  end

  def step
    @x.length
  end
end

o = T_gc_save_double_in_new_GcSaveDoubleInNew.new("a")
puts o.step
