# The classes of a rescue clause are read after the raise, and reading
# one can run code that raises and rescues on its own. The clause that
# matches still has the first exception as `$!`; a clause that misses
# passes it on; and after the region `$!` is what it was before.
def quiet = (raise "inner" rescue :rescued)

x = begin
  raise "one"
rescue quiet.then { RuntimeError } => e
  [:caught, $!.message, e.message, $!.equal?(e)]
end
p x
p $!

# A class whose === raises and rescues inside the test.
module Picky
  def self.===(other)
    (raise ArgumentError, "probe" rescue nil)
    other.is_a?(RuntimeError)
  end
end
y = begin
  raise "two"
rescue Picky
  [:picky, $!.message]
end
p y

# Two clauses miss, each after a nested rescue; the outer rescue gets the
# exception, and its cause is still nil.
z = begin
  begin
    raise IndexError, "three"
  rescue quiet.then { ArgumentError }, quiet.then { TypeError }
    :wrong
  end
rescue IndexError => e
  [:outer, e.message, $!.message, e.cause]
end
p z

# The exception that the classes see as $! during the test is the raise.
seen = nil
w = begin
  raise "four"
rescue (seen = $!&.message; RuntimeError)
  [:four, $!.message]
end
p [w, seen]

# A retry after such a test runs the body again with the old $!.
tries = 0
r = begin
  tries += 1
  raise "five" if tries < 3
  [:done, tries, $!]
rescue quiet.then { RuntimeError }
  retry
end
p r

# In a method, an ensure after such a clause sees the method's $!.
def inside
  begin
    raise "six"
  rescue quiet.then { RuntimeError }
    [:six, $!.message]
  ensure
    $stdout.puts "ensure #{$!.inspect}"
  end
end
p inside
p $!
