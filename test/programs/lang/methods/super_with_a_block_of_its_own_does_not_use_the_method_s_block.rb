$VERBOSE = true
class C0
  def f1 = nil
  def f2 = nil
  def f3 = nil
  def f4 = nil
  def f5 = nil
  def f6 = nil
  def f7 = nil
  def f8 = nil
  def f9 = nil
end

class C1 < C0
  def f1 = super         # zsuper / use
  def f2 = super()       # super  / use
  def f3(&_) = super(&_) # super  / use
  def f4 = super(&nil)   # super  / unuse
  def f5 = super(){}     # super  / unuse
  def f6 = super{}       # zsuper / unuse
  def f7 = super { yield } # a yield inside the block uses it
  def f8
    b = proc {}
    super(&b)            # unuse
  end
  def f9 = super(1) rescue nil # use
end

C1.new.f1 {}
C1.new.f2 {}
C1.new.f3 {}
C1.new.f4 {}
C1.new.f5 {}
C1.new.f6 {}
C1.new.f7 {}
C1.new.f8 {}
C1.new.f9 {}
