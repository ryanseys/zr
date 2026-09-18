# The wasm road has no working directory.
p $LOADED_FEATURES.count { |f| f.include?("requires/lib") }, $LOAD_PATH.select { |d| d.include?("requires") }
p require_relative("requires/lib/one")
p require_relative("requires/lib/one.rb")
p ONE, One.hi
p $LOADED_FEATURES.last.split("/").last, $".equal?($LOADED_FEATURES), $:.equal?($LOAD_PATH)
def pull = require_relative("requires/lib/late")
p defined?(LATE)
p pull, pull, LATE
$LOAD_PATH.unshift(File.expand_path("requires/lib", __dir__))
p require("deep/two")
p require("deep/two")
p Two.where, Two.file == __FILE__
p load(File.expand_path("requires/lib/counted.rb", __dir__)), load(File.expand_path("requires/lib/counted.rb", __dir__))
p $counted
begin
  require_relative "requires/lib/nope"
rescue LoadError => e
  p e.class, e.message.sub(Dir.pwd, ""), e.path.end_with?("lib/nope"), e.backtrace.size
end
begin
  require_relative "requires/lib/boom"
rescue => e
  puts e.message, e.backtrace
end
p require_relative("requires/lib/boom")
begin
  require_relative "requires/lib/returns"
  p RETURNED
rescue => e
  p e
end
p One.dir == File.join(__dir__, "requires/lib")
x = 5
require_relative "requires/lib/locals"
p defined?(x), x
$LOAD_PATH.unshift(File.expand_path("requires/auto", __dir__))
module Bare
  autoload :Widget, "widget"
end
puts "bare defined?\t#{defined?(Bare::Widget).inspect}"
puts "const_defined?\t#{Bare.const_defined?(:Widget)}"
puts "autoload?\t#{Bare.autoload?(:Widget).inspect}"
p Bare.constants
module Nested
  autoload :Deep, "deep"
end
puts "before\t#{$deep_loaded.inspect}"
puts "nested defined?\t#{defined?(Nested::Deep::Inner).inspect}"
puts "after\t#{$deep_loaded.inspect}"
puts "missing nested\t#{defined?(Nested::Deep::Absent).inspect}"
p Bare::Widget.kind, Bare.autoload?(:Widget), $widget_runs
p Bare::Widget.kind, $widget_runs
autoload :TopLevel, "#{__dir__}/requires/auto/top"
p defined?(TopLevel), autoload?(:TopLevel), Object.autoload?(:TopLevel)
p TopLevel, autoload?(:TopLevel)
module Empty
  autoload :Nothing, "nothing"
end
begin
  Empty::Nothing
rescue NameError => e
  puts e.message
end
p Empty.constants
module Holder
  autoload :Late, "late"
  def self.peek = const_get(:Late)
end
p Holder.peek
p Holder.autoload?(:Late)
Kernel.autoload(:Kmod, "kmod")
p Kmod
