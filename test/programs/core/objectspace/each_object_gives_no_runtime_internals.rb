# ObjectSpace.each_object gives no Array that the runtime keeps for
# itself, so every Array it gives can be inspected, also while inspect
# guards against recursion.
GC.disable
eval("begin; 1.times{}; rescue; ensure; end")
arys = []
ObjectSpace.each_object(Array) { |ary| arys << ary }
GC.enable
p arys.all? { |ary| ary.inspect.is_a?(String) }
