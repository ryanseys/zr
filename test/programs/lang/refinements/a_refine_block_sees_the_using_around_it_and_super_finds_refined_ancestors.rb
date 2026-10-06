# A site in a refine block sees the block's refinements, then those of
# the `using` around the block. `super` in a refinement's method starts
# at the refined class and then sees the refinements in use. `[a, b].min`
# under `using` asks a refinement of Array.
class MinMax
  module M
    refine Array do
      def min = :min
      def max = :max
    end
  end
  using M
  def t = [[1 + 0, 2, 4].min, [1, 2, 4].min, [1 + 0, 2, 4].max, [1, 2, 4].max]
end
p MinMax.new.t
module SuperToModule
  class Parent; end
  class Child < Parent; end
  module FooBar
    refine(Parent) { def to_s = "Parent" }
    refine(Child) { def to_s = super + " -> Child" }
  end
  using FooBar
  def Child.test = new.to_s
end
p SuperToModule::Child.test
class RefineInUsing
  module M1
    refine(RefineInUsing) { def foo = :ok }
  end
  module M2
    using M1
    refine(RefineInUsing) { def call_foo = RefineInUsing.new.foo }
  end
  using M2
  def self.test = new.call_foo
end
p RefineInUsing.test
module RefineScoping
  refine String do
    def foo = "foo"
    def RefineScoping.call_in_refine_block = "".foo
  end
  def self.call_outside_refine_block = "".foo
end
p RefineScoping.call_in_refine_block
p((RefineScoping.call_outside_refine_block rescue $!.class))
