# Two writers in different methods of the same class give the ivar
# values of different classes. Here writer 1 in initialize assigns
# an Integer (from a Hash read) and writer 2 in write_any assigns a
# String param. The ivar holds the last value written.

class T_ivar_writer_heterogeneity_C
  def initialize(h)
    @id = h[:id]
  end

  def id; @id; end

  def write_any(value)
    @id = value
  end
end

c = T_ivar_writer_heterogeneity_C.new({id: 42})
c.write_any("string")
puts c.id

# The Integer writer alone still works when no other writer gives a
# different class.
class T_ivar_writer_heterogeneity_D
  def initialize(h)
    @v = h[:v]
  end
  def v; @v; end
end

d = T_ivar_writer_heterogeneity_D.new({v: 7})
puts d.v
