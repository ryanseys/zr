# A class is not a module to the C API either.
class Etc; end
begin
  require "etc"
rescue TypeError => e
  p e.message
end
