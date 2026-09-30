# A parent-class instance method calls another method with an
# implicit self, and a subclass overrides that method. The override
# runs, and its param gets the Hash that the parent passes.

class T_subclass_override_param_propagate_Base
  def reload(row)
    consume(row)
  end
  def consume(_row)
    "base default"
  end
end

class T_subclass_override_param_propagate_Sub < T_subclass_override_param_propagate_Base
  def consume(row)
    row["id"]
  end
end

puts T_subclass_override_param_propagate_Sub.new.reload({"id" => "42"})

# Three-level chain: param flows through two override layers.
class T_subclass_override_param_propagate_Parent
  def kick(payload)
    handle(payload)
  end
  def handle(_p)
    "parent"
  end
end

class T_subclass_override_param_propagate_Mid < T_subclass_override_param_propagate_Parent
  def handle(p)
    "mid:" + p[:name]
  end
end

class T_subclass_override_param_propagate_Leaf < T_subclass_override_param_propagate_Mid
  def handle(p)
    "leaf:" + p[:name]
  end
end

puts T_subclass_override_param_propagate_Mid.new.kick({name: "m"})
puts T_subclass_override_param_propagate_Leaf.new.kick({name: "l"})
