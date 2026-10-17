# ruby loads bundled_gems before the first line, and its LoadError#message
# warns once when the missing library left the default gems (win32ole in
# 4.0). zr's stand-in for that method (lib/zr/runtime/core/exception.rb)
# reads the path as bundled_gems does, but the warning comes only once
# rubygems loads, and a program that never names Gem does not load it.
begin
  require "win32ole"
rescue LoadError => e
  p e.message
end
