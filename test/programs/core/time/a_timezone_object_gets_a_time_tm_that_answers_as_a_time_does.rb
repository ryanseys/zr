# Time::tm: the UTC time without a subsecond that a timezone object's
# methods get (Init_tm), and its own API.
def t(label)
  print label, ": "
  p yield
rescue Exception => e
  puts "#{e.class}: #{e.message}"
end

class Zone
  attr_reader :seen

  def initialize = @seen = []

  def utc_to_local(t)
    @seen << t.class
    t + 3600
  end

  def local_to_utc(t)
    @seen << t.class
    t - 3600
  end

  def abbr(t)
    @seen << [:abbr, t.class]
    "ZZ"
  end
  def name = "Zone/Name"
end

catcher = Object.new
def catcher.utc_to_local(t) = (CAUGHT << t.class; t)
CAUGHT = []
Time.at(0, in: catcher)
tm = CAUGHT.first
t(:name) { [tm.name, tm.superclass, Time.constants.include?(:tm), Time.constants.sort.first(3)] }
z = Zone.new
time = Time.new(2001, 2, 3, 4, 5, 6.5r, z)
t(:fields) { [time.hour, time.utc_offset, time.zone.class] }
t(:seen) { z.seen.uniq }
t(:strftime_Z) { time.strftime("%Z") }
t(:seen_after_abbr) { z.seen.last }
t(:from_time) { m = tm.from_time(Time.at(1_000_000_000, 123_456, :usec)); [m.class, m.to_i, m.usec, m.utc?, m.zone, m.to_s, m.inspect] }
t(:new) { m = tm.new(2001, 2, 3, 4, 5, 6); [m.year, m.mon, m.month, m.mday, m.day, m.hour, m.min, m.sec, m.to_a, m.isdst, m.dst?, m.gmtoff, m.gmt_offset, m.gmt?] }
t(:new_month_name) { tm.new(2001, "feb", 3).to_s }
t(:new_seven) { tm.new(2001, 2, 3, 4, 5, 6, "+09:00").to_s }
t(:new_zero_args) { tm.new }
t(:new_eight_args) { tm.new(1, 2, 3, 4, 5, 6, 7, 8) }
t(:plus) { m = tm.new(2001, 2, 3) + 60; [m.class, m.to_s] }
t(:minus) { m = tm.new(2001, 2, 3) - 60.5; [m.class, m.to_s, m.subsec] }
t(:minus_time) { tm.new(2001, 2, 3) - Time.at(0) }
t(:minus_tm) { tm.new(2001, 2, 3) - tm.new(2001, 2, 2) }
t(:utc) { u = tm.new(2001, 2, 3).utc; [u.class, u.utc?, u.to_s] }
t(:to_time) { tm.new(2001, 2, 3).to_time.class }
t(:conversions) { m = tm.new(2001, 2, 3); [m.to_i, m.to_f, m.to_r, m.tv_sec, m.tv_usec, m.tv_nsec, m.nsec, m.subsec] }
t(:allocate) { tm.allocate.sec }
t(:from_time_bad) { tm.from_time(1) }
t(:not_a_time) { tm.new(2001).is_a?(Time) }
t(:methods) { (tm.instance_methods(false)).sort }
