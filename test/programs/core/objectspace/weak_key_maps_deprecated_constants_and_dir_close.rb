# A WeakKeyMap hashes a key with a private hash. A deprecated constant
# warns when read, when const_get reads it, and when it is removed.
# Closing a Dir whose descriptor another Dir closed raises EBADF.
class KH
  private def hash = 1
end
m = ObjectSpace::WeakKeyMap.new
k = KH.new
m[k] = 42
p m[k]
Warning[:deprecated] = true
mo = Module.new
mo::PUBLIC1 = 1
mo::PRIVATE = 2
mo.private_constant :PRIVATE
mo.deprecate_constant :PRIVATE, :PUBLIC1
def Warning.warn(msg, **) = print(msg.sub(/#<Module:0x\h+>/, "M"))
mo::PUBLIC1
mo.const_get :PRIVATE
p((mo::PRIVATE rescue $!.class))
mo.module_eval { remove_const :PUBLIC1 }
d = Dir.open("/tmp")
d2 = Dir.for_fd(d.fileno)
d.close
p((d2.close rescue $!))
