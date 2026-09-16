# `not v` and `!v` answer inline for nil, true and false while none of
# their classes redefines `!`; any other receiver sends `!` through its
# own site, so a class with its own `!` answers, and a `!` written on
# NilClass, Object or BasicObject reaches the three too.
class Yes
  def !
    :custom
  end
end
class Quiet < BasicObject
  def !
    :quiet
  end
end
p (not nil), (not true), (not false), !nil, !0, !"", ![], !Yes.new, !Quiet.new, (not Yes.new)
p [nil, false, true, 1, :a].map { |v| not v }
def loud(x) = (not x)
p loud(false), loud(Yes.new)
class Object
  def !
    :object
  end
end
p (not nil), (not true), (not false), !3, !"s", (not Yes.new)
class Object
  remove_method :!
end
class NilClass
  def !
    :nil_not
  end
end
p (not nil), (not true), (not false), !nil, !!nil
class NilClass
  remove_method :!
end
p (not nil), (not 1), loud(nil)
o = Object.new
def o.!
  :single
end
p (not o), !o

__END__
true
false
true
true
false
false
false
:custom
:quiet
:custom
[true, true, false, false, false]
true
:custom
:object
:object
:object
:object
:object
:custom
:nil_not
false
true
:nil_not
false
true
false
true
:single
:single
