module R
  refine(String) { def to_s = "refined-str" }
  refine(Symbol) { def to_s = "refined-sym" }
  refine(Integer) { def to_s = "refined-int" }
  refine(NilClass) { def to_s = "refined-nil" }
  refine(Array) { def to_s = "refined-ary" }
end
using R
s = "x"
p ["#{s}", "#{:y}", "#{1}", "#{nil}", "#{[1]}", "a#{s}b", :"#{s}", `echo #{s}`.chomp, /#{s}/.source]
p [s.to_s, :y.to_s, 1.to_s, nil.to_s]
class S2 < String; end
p "#{S2.new("sub")}"
module R2; refine(NilClass) { def to_s = "RN" }; refine(TrueClass) { def to_s = "RT" }; refine(Module) { def to_s = "RM" }; end
using R2
p ["#{}", "#{nil}", "a#{}b", "#{true}", "#{String}", :"#{}"]
x = nil
p ["#{x}", "#{s}#{x}", "#{:"dyn#{1}sym"}"]
