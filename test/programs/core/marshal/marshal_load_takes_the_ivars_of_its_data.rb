# After marshal_load, the object takes the instance variables of the data
# it loaded from, those it does not set itself, before the proc sees it.
# A frozen object refuses them.
class LoadData
  attr_reader :data
  def initialize(data) = @data = data
  alias marshal_dump data
  alias marshal_load initialize
end

class Frozen < LoadData
  def initialize(*)
    super
    freeze
  end
  alias marshal_load initialize
end

s = +"data with ivar"
s.instance_variable_set(:@t, 42)
seen = nil
v = Marshal.load(Marshal.dump(LoadData.new(s)), ->(x) { seen = x.instance_variable_get(:@t) if LoadData === x; x })
p [v.data, v.instance_variable_get(:@t), seen]
begin
  Marshal.load(Marshal.dump(Frozen.new(s)))
rescue => e
  p e.class
end
p Marshal.load(Marshal.dump(Frozen.new("plain"))).data
