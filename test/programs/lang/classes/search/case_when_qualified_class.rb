# `case obj when Mod::Klass`: a qualified constant (`Mod::Klass`) in
# a `when` arm matches the same way as a plain constant.

module Mod
  class Klass
    def initialize(v); @v = v; end
    def get; @v; end
  end
  class Other
    def initialize(v); @v = v; end
    def get; @v; end
  end
end

k = Mod::Klass.new(1)
result = case k
         when Mod::Klass then "match"
         when Mod::Other then "other"
         else "neither"
         end
puts result

# A plain (non-namespaced) class in a `when` arm.
class Plain
  def initialize; @x = 1; end
end
p_inst = Plain.new
result2 = case p_inst
          when Plain then "plain"
          else "?"
          end
puts result2
