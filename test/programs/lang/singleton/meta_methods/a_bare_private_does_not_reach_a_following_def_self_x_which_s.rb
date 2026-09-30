# A bare `private` sets the default only for subsequent INSTANCE defs; a
# singleton def (`def self.name` / `def Recv.name`) that follows is a
# method on another object and stays public. net/protocol's
# `private; def Protocol.protocol_param` is this shape.

class Proto
  private
  def Proto.cls_param; "cls_ok"; end
  def self.self_param; "self_ok"; end
  def inst; "inst"; end
end
puts Proto.cls_param
puts Proto.self_param
begin
  Proto.new.inst
rescue NoMethodError
  puts "inst_private"
end
