# Reading a class variable that was never assigned raises NameError
# ("uninitialized class variable @@missing in ..."). zr's cvar read answers
# nil instead.
class CvarHost
  def self.read
    @@missing
  rescue NameError => e
    "NameError: #{e.message}"
  end
end

puts CvarHost.read.inspect
puts defined?(@@top_missing).inspect
