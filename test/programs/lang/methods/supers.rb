# super inside methods define_method made, and outside any method.
class A
  def hi(x = 1) = "A#hi(#{x})"
  def self.make = "A.make"
end
class B < A
  define_method(:hi) { |x = 2| "B:" + super(x) }
  define_method(:hi2) { |x| [1].map { super(x) rescue $!.class } }
  define_method(:bare) { super }
  define_method(:none) { super() }
  define_singleton_method(:make) { "B:" + super() }
end
p B.new.hi, B.new.hi(5), B.new.hi2(3), B.make
begin; B.new.bare; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; B.new.none; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; super; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; super(); rescue => e; puts "#{e.class}: #{e.message}"; end
class C < A
  def hi(x) = [x].map { super(x) }.first + [x].map { super }.first
  m = instance_method(:hi)
  define_method(:hi3, m)
  define_method(:hi4) { |x| super(x) }
end
p C.new.hi(7), C.new.hi3(8)
begin; C.new.hi4(9); rescue => e; puts "#{e.class}: #{e.message}"; end
class D < C; define_method(:hi4) { |x| super(x) }; end
begin; p D.new.hi4(1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; B.new.bare; rescue => e; puts e.backtrace; end
begin; B.new.hi2(1); rescue => e; puts e.backtrace; end
