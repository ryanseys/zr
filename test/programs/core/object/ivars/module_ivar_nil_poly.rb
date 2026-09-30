# A module-level instance variable initialized to nil and later widened
# to a polymorphic value (it holds nil, an empty [], and a String push).
# The nil initializer is a real nil, not 0.
module Store
  @log = nil

  def self.capture
    prev = @log
    @log = []
    @log.push("select 1")
    @log = prev
  end
end

Store.capture
puts "ok"
