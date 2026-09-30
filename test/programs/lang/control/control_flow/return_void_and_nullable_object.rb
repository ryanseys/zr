# A method that returns nil in every path, with an explicit `return nil`. And a
# method that returns an object or nil, with an early bare `return` (Ruby nil).
# Both compile, and the bare `return` gives nil.

class Pool
  def initialize
    @n = 1
  end
  def n
    @n
  end
end

class Db
  def self.open
    @pool = Pool.new
  end
  def self.close
    return if @pool.nil?
    @pool = nil
  end
  def self.pool
    @pool
  end
end

class Logger
  def self.log(msg)
    return nil if msg.empty?
    puts msg
    nil
  end
end

class Counter
  @count = 0
  def self.bump
    @count = @count + 1
    nil
  end
  def self.count
    @count
  end
  # Method that returns nil in every path: the early `return bump` still
  # calls bump, so its side effect runs.
  def self.tick(run)
    return bump if run
    nil
  end
end

Db.open
p Db.pool.n
Db.close
p Db.pool.nil?
Logger.log("")
Logger.log("hi")

Counter.tick(false)
p Counter.count
Counter.tick(true)
p Counter.count
