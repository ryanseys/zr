# Refinement#import_methods copies a module's methods into the
# refinement, and their code then sees the refinement's own methods, as
# code written in the refinement does. zr compiles the module's code
# once, without the refinement.
class A
  def foo = "original"
end
module B
  def bar = "#{foo}:bar"
end
module C
  refine A do
    import_methods B
    def foo = "refined"
  end
end
module UsingC
  using C
  def self.call_bar = A.new.bar
end
p UsingC.call_bar
