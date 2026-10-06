class MyH < Hash; end
[{}.compare_by_identity.tap { _1["a"] = 1 }, Hash.new(3).compare_by_identity, MyH.new.compare_by_identity.tap { _1[:k] = 2 }].each do |h|
  d = Marshal.dump(h); p d
  x = Marshal.load(d); p [x, x.class, x.compare_by_identity?, x.default]
end
p Marshal.load("\x04\bC:\tHash[\x00") rescue p $!
