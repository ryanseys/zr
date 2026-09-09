ONE = 1
module One
  def self.hi = "hi from #{File.basename(__FILE__)}"
  def self.dir = __dir__
end
