# An object with a `_dump` is remembered only after its instance
# variables, so one that holds itself would be dumped without end;
# Marshal refuses it instead.
time = Time.utc(0)
time.instance_eval { @self = time }
begin
  Marshal.dump(time)
rescue RuntimeError => e
  p [e.class, e.message]
end

class Point
  def initialize(x) = @x = x
  def _dump(_limit) = @x.to_s
  def self._load(text) = new(text.to_i)
  attr_reader :x
end
point = Point.new(4)
p Marshal.load(Marshal.dump([point, point])).map(&:x)
