# `undef` in a refine block undefines a method that the refined class
# has, for the code that uses the refinement only.
module NoPlus
  refine(String) { undef + }
end
module Client
  using NoPlus
  def self.add(a, b) = a + b
  def self.literal = "a" + "b"
end
a = "a"
p((Client.add(a, "b") rescue $!.class))
p((Client.literal rescue $!.class))
p a + "b"
