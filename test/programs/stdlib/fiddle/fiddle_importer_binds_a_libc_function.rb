# Fiddle::Importer binds a C function of the program's own libc by its
# prototype.
require "fiddle/import"
m = Module.new do
  extend Fiddle::Importer
  dlload Fiddle::Handle::DEFAULT
  extern "int abs(int)"
end
p m.abs(-3)
