# A method that Refinement#import_methods copies runs with its refinement
# active, so it calls the refinement's version of a method that the class
# already has. zr compiles the method's sends outside the `refine`, and
# turns the refinement on only for a send that misses, so the copy calls
# String#size here.
utils = Module.new do
  def size = 99
  def report = "size #{size}"
end
Module.new do
  refine(String) { import_methods utils }
  using self
  p "abc".report
end
