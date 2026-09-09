# native only: the wasm road has no working directory
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
