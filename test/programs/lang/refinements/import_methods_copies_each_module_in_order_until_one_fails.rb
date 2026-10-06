# Refinement#import_methods warns for each module first, then copies the
# methods one module at a time: the modules before one with a method that
# is not written in Ruby keep their methods in the refinement.
str_utils = Module.new do
  def indent(level) = " " * level + self
end
string_refined = Module.new do
  refine String do
    import_methods str_utils, Kernel
  rescue ArgumentError => e
    # Kernel lists its methods in another order than ruby.
    p [e.class, e.message.sub(/#\w+\z/, "#")]
  end
end
Module.new do
  using string_refined
  p "foo".indent(3)
end

# A private method is copied as private.
helpers = Module.new do
  def shout = upcase + "!"
  private def whisper = downcase
end
loud = Module.new do
  refine String do
    import_methods helpers
  end
end
Module.new do
  using loud
  p "Hi".shout
  p "Hi".send(:whisper)
  begin
    "Hi".whisper
  rescue NoMethodError => e
    p e.message
  end
end

# A wrong argument stops before any copy.
begin
  Module.new { refine(String) { import_methods str_utils, String } }
rescue TypeError => e
  p e.message
end
