class P; def x(*a) = a; end

class Q < P
  def self.make(a) = define_method(:x) { super }
  make(1)
end
begin
  p Q.new.x
rescue => e
  p e.class, e.message
end

class R < P
  def self.make(a) = define_method(:x) { |*| super }
  make(1)
end
begin
  p R.new.x(5)
rescue => e
  p e.class, e.message
end

class V < P
  define_method(:x) { super }
end
begin
  p V.new.x
rescue => e
  p e.class, e.message
end

# A block of a def keeps the def's arguments.
class S < P
  def x(a) = [1].map { super }
end
p S.new.x(7)

class U < P
  def x(a)
    pr = proc { super }
    pr.call
  end
end
p U.new.x(9)

class T < P
  define_method(:x) { |a| super(a, 2) }
end
p T.new.x(3)

