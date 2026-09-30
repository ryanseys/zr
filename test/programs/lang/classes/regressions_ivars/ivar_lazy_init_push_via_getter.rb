# `@ivar = [] if @ivar.nil?` plus push-through-getter: a push
# through the getter method adds String values to the ivar's Array.
#
# Coverage:
#   - The canonical Rails-style `ActiveRecord::Base#errors`
#     shape: lazy-init via nil guard, push via a sibling
#     `add_error` method that calls `errors << "..."`.
#   - Same shape with `self.<getter>` (explicit self-recv) so
#     both the bare and self-prefixed call forms route to the
#     ivar.

class T_ivar_lazy_init_push_via_getter_Errors
  def list
    @list = [] if @list.nil?
    @list
  end

  def add(msg)
    list << msg
  end
end

class T_ivar_lazy_init_push_via_getter_ErrorsSelf
  def list
    @list = [] if @list.nil?
    @list
  end

  def add(msg)
    self.list << msg
  end
end

e = T_ivar_lazy_init_push_via_getter_Errors.new
e.add("a")
e.add("b")
puts e.list.length
puts e.list[0]
puts e.list[1]

es = T_ivar_lazy_init_push_via_getter_ErrorsSelf.new
es.add("x")
puts es.list[0]
