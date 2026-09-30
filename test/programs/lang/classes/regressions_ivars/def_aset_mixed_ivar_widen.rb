# `def []=(name, value)` whose body dispatches on `name` and writes
# `value` into ivars of differing types (`@id = value` and
# `@name = value`, where `@id` holds an Integer and `@name` a String).
# The param takes each value, and each ivar keeps the value it gets.

class T_def_aset_mixed_ivar_widen_Foo
  def initialize
    @id = 0
    @name = ""
  end

  def []=(name, value)
    case name
    when :id
      @id = value
    when :name
      @name = value
    end
  end

  def id
    @id
  end

  def name
    @name
  end
end

f = T_def_aset_mixed_ivar_widen_Foo.new
f[:id] = 42
f[:name] = "hello"
puts f.id
puts f.name
