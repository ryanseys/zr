require_relative "counter/part"

module Counter
  @count = 0

  def self.bump = @count += 1
  def self.count = @count
end
