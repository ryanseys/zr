# Marshal.dump checks its port and calls binmode, refuses a singleton
# with ivars, dumps a BasicObject subclass; load reads encoded ivar names.
def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
o = Object.new
def o.foo = 1
show(2) { Marshal.dump(o) }
o2 = Object.new
o2.singleton_class.instance_variable_set(:@x, 1)
show(3) { Marshal.dump(o2) }
class BasicSub < BasicObject
  def respond_to?(*) = false
end
show(4) { Marshal.dump(BasicSub.new).bytesize }
w = Object.new
show(5) { Marshal.dump("x", w) }
bm = Object.new
def bm.write(s) = nil
def bm.binmode = (puts "binmode"; self)
show(6) { Marshal.dump("x", bm); :ok }
show(7) { Marshal.load("\x04\bo:\vObject\x06I:\b@\xC3\xA9\x06:\x06ETi\x06".b).instance_variables }
