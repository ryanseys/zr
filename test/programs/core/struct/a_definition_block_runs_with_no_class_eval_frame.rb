# Struct.new and Data.define run their block under the new class from C,
# so an error in it shows no frame of class_eval.
def labels(e) = e.backtrace_locations.map(&:label)
begin; Struct.new(:a) { missing_thing }; rescue NameError => e; p labels(e); end
begin; Data.define(:a) { missing_thing }; rescue NameError => e; p labels(e); end
S = Struct.new(:a) do
  def twice = a * 2
  p [self.is_a?(Class), self.class]
end
p S.new(3).twice
D = Data.define(:b) { def half = b / 2 }
p D.new(b: 8).half
x = 5
p Struct.new(:c) { define_method(:x) { x } }.new(1).x
