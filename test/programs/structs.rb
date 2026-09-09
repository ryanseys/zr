S = Struct.new(:a, :b) do
  def initialize(*args)
    super
    raise "x" if a == 9
  end
end
begin; S.new(9); rescue => e; puts e.backtrace; end
p S.singleton_methods(false).sort
p S.instance_methods(false).sort
p Struct.instance_methods(false).sort
p Struct.singleton_methods.sort
p S.new(1)
p S.new(1, 2).to_a, S.members, S.new(1).frozen?
s = S.new(1, 2)
p s.instance_variables
p S.new(1, 2) == S.new(1, 2), S.new(1, 2).eql?(S.new(1, 2)), S.new(1,2).hash == S.new(1,2).hash
p s[0], s[:a], s["b"], s[-1]
begin; s[2]; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; s[:c]; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; s["c"]; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; s[-3]; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; S.new(1,2,3); rescue => e; puts "#{e.class}: #{e.message}"; end
s.freeze
begin; s.a = 3; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; s[:a] = 3; rescue => e; puts "#{e.class}: #{e.message}"; end
K = Struct.new(:x, keyword_init: true)
p K.new(x: 1), K.keyword_init?, S.keyword_init?
begin; K.new(1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; K.new(y: 1); rescue => e; puts "#{e.class}: #{e.message}"; end
p S.new(a: 1, b: 2)
begin; S.new(1, b: 2); rescue => e; puts "#{e.class}: #{e.message}"; end
p Struct.new("Named", :q).new(1)
p Struct::Named
begin; Struct.new("lower"); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Struct.new(:a, :a); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Struct.new; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Struct.new(1); rescue => e; puts "#{e.class}: #{e.message}"; end
p s.to_h, s.each.to_a, s.each_pair.to_a, s.values_at(0, 1), s.size, s.dig(:a)
p s.to_h { |k, v| [k.to_s, v * 2] }
p Struct.new(:a).new(1).inspect, Struct.new(:a).new(1).to_s
p s.deconstruct, s.deconstruct_keys([:a]), s.deconstruct_keys(nil)
p S.new(1, 2).select(&:odd?)
p S[3, 4]
d = S.new([1], 2).dup; d.a << 5; p d
c = S.new(1,2); d = c.dup; d.a = 7; p c, d
p S.superclass, S.new(1).is_a?(Struct), S.new(1).class.ancestors.take(3)
class Sub < S; def sum = a + b; end
p Sub.new(1, 2).sum, Sub.new(1, 2), Sub.members
p S.new(1, 2).each_pair { }
p S.new("a", 2).inspect
R = Struct.new(:r); r = R.new; r.r = r; p r
p S.new(1,2).filter_map { |v| v if v > 1 }
p s.members
begin; S.new(1,2).instance_variable_get(:@__members__); rescue => e; puts "#{e.class}: #{e.message}"; end
p S.new(1, 2).to_a.frozen?
p S.new(1, 2).values
