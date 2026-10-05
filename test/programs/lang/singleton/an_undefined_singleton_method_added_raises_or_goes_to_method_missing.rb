# A singleton method on an object whose singleton_method_added is
# undefined calls the hook anyway: NoMethodError, or method_missing.
class NoAdd
  class << self
    undef_method :singleton_method_added
  end
  begin
    def self.foo = 1
  rescue NoMethodError => e
    p e.message[/undefined method '\w+'/]
  end
end
ob = Object.new
class << ob
  undef_method :singleton_method_added
end
p(((def ob.bar = 1) rescue $!.class))
mm = Object.new
class << mm
  undef_method :singleton_method_added
  def method_missing(*a) = (($calls ||= []) << a; nil)
end
def mm.baz = 1
p $calls
