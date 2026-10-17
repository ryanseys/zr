# A `require` that the program defines with define_method, as a test's
# stand-in does, hears each require and decides what it returns. Once
# the program puts the first `require` back, a require runs as before. A
# `require` of a prepended module hears each one too, and its `super`
# loads the file.
original = Kernel.instance_method(:require)
heard = []
Kernel.send(:define_method, :require) do |name|
  heard << name
  raise LoadError, "cannot load such file -- #{name}" if name == "time"

  :stood_in
end
p require("tsort"), defined?(TSort)
begin
  require "time"
rescue LoadError => e
  p e.message
end
p heard
Kernel.send(:define_method, :require, original)
p require("tsort"), defined?(TSort)

module Loud
  def require(name)
    puts "loud #{name}"
    super
  end
end
Object.prepend(Loud)
p require("pp"), require("English"), defined?($PROGRAM_NAME)
