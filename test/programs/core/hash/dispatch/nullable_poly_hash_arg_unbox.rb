# A hash with Symbol keys and mixed values, or nil. After a nil
# guard, a value read with `[]` goes to a method that takes an
# Integer, and the method gets that Integer.
#
# The shape comes from a blog app:
#   matched = Router.match(...)
#   return if matched.nil?           # matched is a Hash here
#   controller = Main.instantiate_controller(matched[:controller])
#   controller.process_action(matched[:action])
# It covers a module method call and a call on a receiver that can
# be of more than one class.

module Counter
  def self.double(n)
    n * 2
  end
end

class A
  def act(n)
    n + 100
  end
end

class B
  def act(n)
    n + 200
  end
end

def fetch(present)
  if present
    { value: 21, label: "x" }
  else
    nil
  end
end

def pick(flag)
  if flag
    A.new
  else
    B.new
  end
end

m = fetch(true)
if m.nil?
  puts "missing"
else
  # Module class method call.
  puts Counter.double(m[:value])
  # Call on a receiver that can be an A or a B.
  puts pick(true).act(m[:value])
  puts pick(false).act(m[:value])
end

# Same shape with String keys and mixed values, or nil.
def fetch_str(present)
  if present
    { "k1" => 7, "k2" => "v" }
  else
    nil
  end
end

s = fetch_str(true)
if s.nil?
  puts "missing"
else
  puts Counter.double(s["k1"])
end
