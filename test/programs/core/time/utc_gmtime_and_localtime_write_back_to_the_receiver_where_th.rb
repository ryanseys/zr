# Time#utc / #gmtime / #localtime change the receiver, a local or an ivar.
# The get* flavors do not change it. The example does not check a change
# seen through a second variable that refers to the same Time.
v = Time.at(0)
v.utc
p v.utc?
w = Time.at(0)
w.gmtime
p w.utc?
x = Time.utc(2020, 1, 1)
x.localtime
p x.utc?
y = Time.at(0)
p y.utc.utc?
z = Time.at(0)
z.getutc
p z.utc?
class Holder
  def initialize; @t = Time.at(0); end
  def flip; @t.utc; end
  def utc?; @t.utc?; end
end
h = Holder.new
h.flip
p h.utc?
