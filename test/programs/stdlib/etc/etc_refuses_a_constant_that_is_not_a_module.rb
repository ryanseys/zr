# The extension defines Etc with the C API, whose message names the
# class of the value the constant already holds.
class Cell; end
Etc = Cell.new
begin
  require "etc"
rescue TypeError => e
  p e.message
end
p Etc.class
