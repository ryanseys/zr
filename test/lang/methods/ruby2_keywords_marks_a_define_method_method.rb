class Base
  def m(a = nil, k: :default) = [a, k]
end
class ViaDefine < Base
  define_method(:m) { |*args, &blk| super(*args, &blk) }
  ruby2_keywords(:m)
end
p ViaDefine.new.m(k: 1), ViaDefine.new.m(2)
class ViaDef < Base
  ruby2_keywords def m(*args, &blk) = super(*args, &blk)
end
p ViaDef.new.m(k: 3)
class Forward
  define_method(:call) { |*args| target(*args) }
  ruby2_keywords(:call)
  def target(x = 0, y: 9) = [x, y]
end
p Forward.new.call(y: 4), Forward.new.call(5)
p Hash.ruby2_keywords_hash?(ViaDefine.instance_method(:m).then { |um| Class.new(Base) { define_method(:m) { |*a| a.last }; ruby2_keywords(:m) }.new.m(z: 1) })

__END__
[nil, 1]
[2, :default]
[nil, 3]
[0, 4]
[5, 9]
true
