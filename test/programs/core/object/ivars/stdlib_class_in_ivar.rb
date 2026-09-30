# A stdlib class held in an ivar. A required library (ipaddr) works. A `.new`
# on a stdlib class that the program does not require (OpenStruct) raises
# NameError, as in CRuby. It is never an inert value.
#
# Mutex is core (no require needed), and user-defined classes are unaffected.

require "ipaddr"

class WithMutex
  def initialize
    @lock = Mutex.new   # special-cased no-op; works
    @n = 5
  end
  def n
    @n
  end
end

class WithIPAddr
  def initialize
    @addr = IPAddr.new('127.0.0.1')   # a required stdlib class
    @v = 7
  end
  def v
    @v
  end
end

# A Mutex ivar works (single-threaded no-op); another ivar reads fine.
puts WithMutex.new.n          #=> 5

# A user-defined class is unaffected.
class Point
  def initialize(x)
    @x = x
  end
  def x
    @x
  end
end

class Holder
  def initialize
    @p = Point.new(42)
  end
  def px
    @p.x
  end
end

puts Holder.new.px            #=> 42

# Constructing the IPAddr holder works, because the program requires ipaddr.
begin
  WithIPAddr.new
  puts "no raise"
rescue NameError
  puts "ipaddr raised"
end

# A direct `.new` on a stdlib class that is not required raises NameError.
begin
  OpenStruct.new
  puts "no raise"
rescue NameError
  puts "openstruct raised"
end

puts "done"
