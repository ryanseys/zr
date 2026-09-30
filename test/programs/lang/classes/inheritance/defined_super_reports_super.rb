# `defined?(super)` answers "super" when a super method exists from the
# current method's position and nil when none does. It does not answer
# "method", because `super` is not a plain method reference.
class DefBase
  def probe
    defined?(super).inspect
  end
end

class DefKid < DefBase
  def probe
    defined?(super).inspect
  end
end

puts DefKid.new.probe
puts DefBase.new.probe
