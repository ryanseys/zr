# `not` and `!` on every kind of receiver, before and after the classes
# nil, true and false stand under gain a `!` of their own, and mixed
# with the operators whose gates flip on redefinition.
vals = [nil, false, true, 0, 1, -1, 1.5, 0.0, :sym, "", "s", [], {}, Object.new, 1 << 70, (1..2), Struct.new(:a).new(1)]
show = ->(tag) { p [tag, vals.map { |v| !v }, vals.map { |v| not v }, vals.map { |v| !!v }] }
show.(:plain)
class TrueClass
  def !
    :not_true
  end
end
show.(:true_redefined)
class TrueClass
  remove_method :!
end
module Kernel
  def !
    :kernel_not
  end
end
show.(:kernel)
module Kernel
  remove_method :!
end
class Integer
  alias_method :plus_before, :+
  def !
    :int_not
  end
  def +(o) = :plus
end
show.(:integer)
p 1 + 2, 1.5 + 2, (not 1), !1, !2.5
class Integer
  remove_method :!
  alias_method :+, :plus_before
end
p 1 + 2, !1, (not nil)
class BasicObject
  alias_method :bang_before, :!
  def !
    :basic
  end
end
show.(:basic)
class BasicObject
  alias_method :!, :bang_before
  remove_method :bang_before
end
show.(:restored)
x = nil
p((not x), (not not x), (!x ? 1 : 2), [x].map(&:!), (not (x.nil? and true)))



