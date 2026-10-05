# A Time in a timezone object asks the object's dst? with the time in
# UTC, and Marshal.load keeps a zone name that find_timezone does not
# know as a String instead of raising.
class Zone
  def initialize(name, std, dst) = (@name, @std, @dst = name, std, dst)
  attr_reader :name
  def dst?(t) = (4..9).cover?(t.mon)
  def offset(t) = dst?(t) ? @dst : @std
  def utc_to_local(t) = t + offset(t)
  def local_to_utc(t) = t - offset(t)
  def abbr(t) = dst?(t) ? "PDT" : "PST"
end

zone = Zone.new("America/Los_Angeles", -8 * 3600, -7 * 3600)
summer = Time.new(2018, 6, 22, 12, 0, 0, zone)
winter = Time.new(2018, 12, 22, 12, 0, 0, zone)
p [summer.dst?, summer.utc_offset, winter.dst?, winter.utc_offset, summer.to_a[8]]

class NamedTime < Time
  def self.find_timezone(name) = name == "America/Los_Angeles" ? Zone.new(name, -8 * 3600, -7 * 3600) : raise(ArgumentError, "Unknown timezone: #{name}")
end
data = ["\x04\x08Iu:".b, Marshal.dump(NamedTime)[3..], "\x0d\xEF\xA7\x1D\x80\x00\x00\x00\x00".b,
        Marshal.dump({ offset: 9 * 3600, zone: "JST" })[3..]].join
t = Marshal.load(data)
p [t.utc_offset, (t + 1).utc_offset, t.zone]
