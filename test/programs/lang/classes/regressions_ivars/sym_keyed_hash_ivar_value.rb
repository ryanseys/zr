# A `{ sym_key: <ivar-or-param> }` hash literal whose values are NOT
# string literals -- ivars, params, method-call results. A read by
# key gives the String value.
#
# Coverage:
#   - a Symbol-keyed Hash with a value from an ivar.
#   - a Symbol-keyed Hash with a value from a method param.
#   - an attributes Hash with a value from a method call.

class T_sym_keyed_hash_ivar_value_Foo
  attr_reader :title

  def initialize
    @title = "hello"
  end

  def attributes
    { title: @title }
  end

  def with_extra(more)
    { title: @title, extra: more }
  end
end

f = T_sym_keyed_hash_ivar_value_Foo.new
puts f.attributes[:title]       # hello
puts f.with_extra("world")[:extra]  # world

class T_sym_keyed_hash_ivar_value_Bar
  def initialize
    @body = "lorem"
  end

  def to_h
    { body: @body, len: @body.length.to_s }
  end
end

b = T_sym_keyed_hash_ivar_value_Bar.new
puts b.to_h[:body]              # lorem
puts b.to_h[:len]               # 5
