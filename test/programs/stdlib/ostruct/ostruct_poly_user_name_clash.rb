# An OpenStruct member read must work even when a user class defines a
# method of the same name. The call goes to the OpenStruct member.
require "ostruct"
class Main
  def name = "main-name"
  def parse(h)
    options = h
    return OpenStruct.new(options)
    nil
  end
end
o = Main.new.parse({"name" => "lee"})
p o.name
