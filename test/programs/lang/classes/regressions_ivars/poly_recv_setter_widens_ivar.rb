# `recv.attr = val` where `recv` comes from `case ... when X
# then T_poly_recv_setter_widens_ivar_A.new; when Y then T_poly_recv_setter_widens_ivar_B.new`. The setter
# stores the Hash with String keys and values in `@data`, which
# initialize set to `{}`. A later read gives the stored Hash.

class T_poly_recv_setter_widens_ivar_Base
  attr_accessor :data
  def initialize
    @data = {}
  end
end

class T_poly_recv_setter_widens_ivar_A < T_poly_recv_setter_widens_ivar_Base
end

class T_poly_recv_setter_widens_ivar_B < T_poly_recv_setter_widens_ivar_Base
end

# A case-expression whose branches return different sibling
# subclasses.
n = 1
receiver = case n
           when 0 then T_poly_recv_setter_widens_ivar_A.new
           when 1 then T_poly_recv_setter_widens_ivar_B.new
           end
merged = { "name" => "foo" }
receiver.data = merged
puts receiver.data["name"]
