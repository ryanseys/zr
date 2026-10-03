begin
  require "cp_util"
rescue LoadError => e
  puts e.message
end
$LOAD_PATH.unshift File.expand_path("conditional_path/vendor") if ENV["NO_SUCH_VARIABLE"]
begin
  require "cp_util"
rescue LoadError => e
  puts e.message
end
$LOAD_PATH.unshift File.expand_path("conditional_path/vendor")
require "cp_util"
