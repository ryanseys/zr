# An instance_eval string on a value with no singleton class of its own
# (nil, 7, :sym) reads class variables from the scope around the call,
# as vm_get_cvar_base passes over the cref an eval pushed (test_eval.rb's
# test_instance_eval_cvar). A def there raises for a value that can
# have no singleton class.
class T
  @@cvar = 13
  def self.run
    [Object.new, [], 7, :sym, true, false, nil, 1.5].each do |obj|
      p [obj.instance_eval("@@cvar"), obj.instance_eval { @@cvar }, obj.instance_eval("self").equal?(obj) || obj.instance_eval("self") == obj]
    end
    Integer.class_eval "@@zr_scope = 1"
    @@zr_scope = 4
    p 1.instance_eval("@@zr_scope")
    [1, :s, nil].each do |obj|
      obj.instance_eval("def zr_x = 1")
      p [obj, obj.zr_x]
    rescue TypeError => e
      p [obj, e.message]
    end
    p nil.instance_eval("Integer"), 1.instance_eval("Comparable")
  end
end
T.run
