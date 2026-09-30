# One `@x ||= v` site serves a plain object, then a module and a class that
# extend the same helper. The object's rows live in its cell; a module's or
# class's live in its extension, so a site that has learned the object's
# rows must not write a module's cell as if it were an object's.
module Tagging
  def tag!
    @first ||= 1
    @second ||= 2
    @third ||= 3
    [@first, @second, @third]
  end
end
class Obj; include Tagging; end
module M; extend Tagging; end
class K; extend Tagging; end

p Obj.new.tag!
p M.tag!
p [M.name, M.ancestors, M.instance_variables, M.class]
p K.tag!
p [K.name, K.superclass, K.ancestors, K.instance_variables, K.new.class]
p [M.tag!, K.tag!, Obj.new.tag!]
module M
  def self.more = [@first, @fourth ||= 4, instance_variables]
end
p M.more

