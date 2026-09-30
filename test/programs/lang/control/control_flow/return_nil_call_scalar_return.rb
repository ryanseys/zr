# A method whose return type is a concrete scalar (here Integer, pinned by the
# `42` branch) but one branch's value is a call that resolves to nil through a
# nil/unresolved receiver. The method must still compile. The nil branch never
# runs here.
module AR
  def self.adapter
    nil
  end
end

class Base
  def self.count(flag)
    if flag
      42
    else
      AR.adapter.count("x")   # nil receiver -> nil into the Integer return
    end
  end
end

puts Base.count(true).to_s
