# An ivar set to `{}` takes a captured `&block` proc as a value.

class T_proc_hash_value_Registry
  def initialize
    @builtins = {}
  end

  def define_builtin(name, &block)
    @builtins[name] = block
  end
end

r = T_proc_hash_value_Registry.new
r.define_builtin("x") { 1 }
puts "ok"
