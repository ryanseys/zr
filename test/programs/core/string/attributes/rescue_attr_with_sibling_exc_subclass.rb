# Reading a rescued exception's attr works when the program defines a
# SECOND, unrelated exception subclass. The second subclass's `initialize`
# `message` param can be any value (its own call sites do not fix its type),
# and `super(message)` still sets the message.

class AError < StandardError
  attr_reader :code
  def initialize(message, code: 3)
    super(message)
    @code = code
  end
end

class BError < StandardError
  attr_reader :level
  def initialize(message, level = 7)
    super(message)
    @level = level
  end
end

begin
  raise AError.new("boom", code: 9)
rescue AError => ea
  puts ea.code
  puts "code is #{ea.code}"
end

begin
  raise BError.new("bad", 5)
rescue BError => eb
  puts eb.level
  puts "msg=#{eb.message} level=#{eb.level}"
end
