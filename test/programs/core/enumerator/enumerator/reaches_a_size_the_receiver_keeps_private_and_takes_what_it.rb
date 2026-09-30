# `enum_size` asks with rb_check_funcall, which calls a method the
# receiver keeps private and takes whatever comes back as it stands.
class Quiet
  include Enumerable
  def each = block_given? ? (yield 1) : to_enum(:each)
  private def size = 99
end

class Odd
  include Enumerable
  def each = block_given? ? (yield 1) : to_enum(:each)
  def size = "nine"
end

p Quiet.new.map.size
p Odd.new.map.size
