# Time takes a timezone object (local_to_utc, utc_to_local) wherever it
# takes a zone, finds one by name through find_timezone, and marshals it
# by name; arithmetic and rounding give a Time, <=> asks a non-Time,
# and a given usec drops the seconds' fraction.
ENV["TZ"] = "UTC"
def t
  yield
rescue => e
  [e.class, e.message]
end
class Tz
  def initialize(offset) = @offset = offset
  def local_to_utc(t) = t - @offset
  def utc_to_local(t) = t + @offset
end
class NamedTz < Tz
  attr_reader :name
  def initialize(name, offset, abbr) = (super(offset); @name = name; @abbr = abbr)
  def abbr(_) = @abbr
end
class FindTime < Time
  def self.find_timezone(name) = NamedTz.new(name.to_s, 19800, "IST")
end
z = Tz.new(3600)
a = Time.new(2000, 1, 1, 12, 0, 0, z)
p a.utc_offset, a.zone.class, a.to_s, a.hour, a.utc.hour
b = Time.new(2000, 1, 1, 12, 0, 0, in: NamedTz.new("Asia/X", 7200, "XST"))
p b.utc_offset, b.zone.name, b.strftime("%H:%M %Z %z")
p((b + 3600).utc_offset, (b + 3600).zone.class, (b - 60).hour)
c = Time.at(0, in: z)
p c.hour, c.utc_offset
p Time.utc(2000).localtime(z).hour, Time.utc(2000).getlocal(z).utc_offset
p FindTime.new(2000, 1, 1, 0, 0, 0, "Asia/Kolkata").utc_offset
m = Marshal.load(Marshal.dump(b))
p m.zone, m.utc_offset
p((Marshal.dump(a) rescue $!.class))
lt = Object.new
def lt.local_to_utc(t) = Time.utc(t.year, t.mon, t.day, t.hour, t.min, t.sec) - 3600
p Time.new(2000, 1, 1, 12, 0, 0, lt).utc_offset
li = Object.new
def li.local_to_utc(t) = Struct.new(:to_i, :zone, :utc_offset).new(t.to_i, "X", 99)
p Time.new(2000, 1, 1, 12, 0, 0, li).utc_offset
ti = Object.new
def ti.local_to_utc(t) = Time.new(t.year, t.mon, t.mday, t.hour, t.min, t.sec, 9 * 3600)
p Time.new(2000, 1, 1, 12, 0, 0, ti).utc_offset
far = Object.new
def far.local_to_utc(t) = Time.utc(t.year, t.mon, t.day + 1, t.hour, t.min, t.sec)
p t { Time.new(2000, 1, 1, 12, 0, 0, far) }
rec = []
r = Object.new
r.define_singleton_method(:local_to_utc) { |x| rec << x; x }
Time.new(2000, 1, 1, 12, 0, 0, r)
x = rec.first
p [x.year, x.mon, x.mday, x.hour, x.min, x.sec, x.usec, x.utc_offset, x.zone, x.to_i]
p Time.now(in: z).utc_offset
class MyTime < Time; end
m = MyTime.at(0)
p((m + 1).class, (m - 1).class, m.floor.class, m.ceil.class, m.round.class, MyTime.at(Time.at(5)).class)
p((Time.at(Time.at(0), 1) rescue [$!.class, $!.message]))
t = Time.utc(2000)
gt = Object.new
def gt.<=>(o) = 1
lt = Object.new
def lt.<=>(o) = -1
eq = Object.new
def eq.<=>(o) = 0
nn = Object.new
def nn.<=>(o) = nil
p t <=> gt, t <=> lt, t <=> eq, t <=> nn, t <=> 5
x = Time.utc(2000, 1, 1, 20, 15, 1.75, 2)
p x.sec, x.usec, x.nsec
y = Time.utc(2000, 1, 1, 20, 15, 1.75, Rational(99, 10))
p y.usec, y.nsec
mo = Object.new
def mo.to_str = "12"
p Time.utc(2008, mo) == Time.utc(2008, 12), Time.utc(2008, "dec").month
class Tz2
  attr_reader :name
  def initialize(name) = @name = name
  def local_to_utc(t) = t - 19800
  def utc_to_local(t) = t + 19800
end
class FindTime2 < Time
  def self.find_timezone(name) = Tz2.new(name.to_s)
end
t = FindTime2.new(2000, 1, 1, 12, 0, 0, Tz2.new("Asia/Colombo"))
l = Marshal.load(Marshal.dump(t))
p l.zone.class, l.zone.name, l.utc_offset
p((Time.new(2000, 1, 1, 0, 0, 0, "-04:10".encode("UTF-16LE")) rescue $!.class))
p((Time.utc(2000).getlocal("-04:10".encode("UTF-16LE")) rescue $!.class))
o = Object.new
def o.local_to_utc(t) = t
p((Time.now(in: o) rescue [$!.class, $!.message]))
u = Object.new
def u.utc_to_local(t) = t
p((Time.new(2000, 1, 1, 0, 0, 0, u) rescue [$!.class, $!.message]))
