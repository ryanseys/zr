# An ivar set to `{}` takes later `@h[k] = "string"` writes. A read
# gives back the String, and a missing key gives nil.

class T_empty_hash_ivar_string_value_Sources
  def initialize
    @file_sources = {}
    @current_file = "a.rb"
  end

  def add(source)
    @file_sources[@current_file] = source if @current_file
  end

  def lookup(name)
    @file_sources[name]
  end
end

s = T_empty_hash_ivar_string_value_Sources.new
s.add("body")
puts s.lookup("a.rb")        # body
puts s.lookup("missing")     # (empty line — a missing key gives nil)

# Integer keys with String values.
class T_empty_hash_ivar_string_value_IntKeyed
  def initialize; @h = {}; end
  def put(k, v); @h[k] = v; end
  def get(k); @h[k]; end
end

ik = T_empty_hash_ivar_string_value_IntKeyed.new
ik.put(7, "seven")
ik.put(42, "forty-two")
puts ik.get(7)               # seven
puts ik.get(42)              # forty-two
