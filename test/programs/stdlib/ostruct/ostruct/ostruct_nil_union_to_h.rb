# to_h on a value that is an OpenStruct or nil gives the OpenStruct's members
# as a Hash.
require "ostruct"
class Main
  def parse(flag)
    return OpenStruct.new(name: "lee") if flag
    nil
  end
end
options = Main.new.parse(true)
raise "FAIL" if options.to_h.key?(:help)
p options.to_h.key?(:name)
h = options.to_h
p h[:name]
puts "OK"
