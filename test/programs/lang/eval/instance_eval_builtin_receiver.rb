# instance_eval / instance_exec with a block on a BUILTIN receiver: the block
# runs with self set to the receiver. Receiverless calls go to the new self
# (Kernel methods such as puts still work), and the call's value is the
# block's value. A user-object receiver also gives access to its ivars.
p "abc".instance_eval { upcase }
p 5.instance_eval { self + 1 }
p [1, 2].instance_eval { length * 10 }
p "xy".instance_exec(3) { |n| self * n }
p "s".instance_eval { |s| s + "!" }
p "abc".instance_eval { self.upcase }
p "hi".instance_eval { puts upcase; length }
x = "abc".instance_eval { 1 + 1 }
p x
# multi-statement body with locals
p("ab".instance_eval do
  u = upcase
  "#{u}/#{length}"
end)
# user-object receivers still ride the ivar-aware path
class W
  def initialize; @v = 7; end
  def get; @v; end
end
p W.new.instance_eval { @v + 1 }
p W.new.instance_eval { get * 2 }
