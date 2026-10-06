# Symbol#to_proc sees no refinement of its caller, while `&:name` at a
# site does. `using` in a block with no Module is a TypeError.
class RefinedScope
  using(Module.new { refine(Integer) { def itself = 0 } })
  ITSELF = :itself.to_proc
  def self.mapped = [1].map(&:itself)
end
p RefinedScope::ITSELF[1], RefinedScope.mapped
begin
  Module.new { using(1) {} }
rescue TypeError => e
  p e.message
end
begin
  using(1) do end
rescue TypeError => e
  p e.message
end
