# Module#autoload? looks through the ancestors, included modules too,
# unless inherit is false.
module M
  def setup = autoload(:Later, "/no/such/later.rb")
end
class C
  include M
end
class D < C; end
C.new.setup
p M.autoload?(:Later), C.autoload?(:Later), D.autoload?(:Later), D.autoload?(:Later, false)
Object.autoload(:Top, "/no/such/top.rb")
p String.autoload?(:Top), String.autoload?(:Top, false)
