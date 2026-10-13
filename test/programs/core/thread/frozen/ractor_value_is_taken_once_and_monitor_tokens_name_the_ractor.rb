# Ractor#value gives the block's value as it is (no copy), once, and only
# to the first ractor that asks (the successor). join waits through a
# port of the caller's own and raises a failure, which takes the value.
# A monitor port gets [ractor, :exited] or [ractor, :aborted]. receive,
# Port#receive and select take a timeout, after which they give nil.
# Each ractor numbers its own ports from 0, its default port.
Warning[:experimental] = false
Thread.report_on_exception = false
def try(label)
  print label, ": "
  p yield
rescue Exception => e
  puts "#{e.class}: #{e.message}#{" (cause #{e.cause.class}: #{e.cause.message})" if e.cause}"
end

p Ractor.current.default_port
p Ractor::Port.new
r = Ractor.new { 42 }
try("value") { r.value }
try("value again") { r.value }
try("join after value") { r.join.equal?(r) }
r = Ractor.new { raise "boom" }
try("aborted value") { r.value }
try("aborted value again") { r.value }
try("aborted join after") { r.join }
r = Ractor.new { raise "boom2" }
try("aborted join") { r.join }
try("aborted join again") { r.join }
try("aborted value after join") { r.value }
r = Ractor.new { :ok }
try("join") { r.join.equal?(r) }
try("join again") { r.join.equal?(r) }
try("value after join") { r.value }
r = Ractor.new { s = +"x"; Ractor.main.send(s.object_id); s }
id = Ractor.receive
try("by reference") { r.value.object_id == id }
r = Ractor.new { :a }
other = Ractor.new(r) { |x| x.value rescue [$!.class, $!.message] }
try("other takes") { other.value }
try("then main") { r.value }
port = Ractor::Port.new
p port
r = Ractor.new { :done }
r.monitor(port)
try("monitor token") { t = port.receive; [t.class, t.size, t[0].equal?(r), t[1]] }
r = Ractor.new { raise "x" }
r.monitor(port)
try("monitor abort token") { t = port.receive; [t[0].equal?(r), t[1]] }
r.join rescue nil
try("monitor after end") { [r.monitor(port), port.receive.then { |t| [t[0].equal?(r), t[1]] }] }
r = Ractor.new { :sel }
try("select ractor") { a, b = Ractor.select(r); [a.equal?(r), b] }
try("value after select") { r.value }
r = Ractor.new { raise "sel" }
try("select aborted") { a, b = Ractor.select(r); [a.equal?(r), b] }
try("value after select aborted") { r.value }
r = Ractor.new { Ractor.receive }
try("unmonitor") { r.unmonitor(port).equal?(r) }
r.send(1)
try("value 1") { r.value }
try("receive timeout") { Ractor.receive(timeout: 0.05) }
try("port receive timeout") { Ractor::Port.new.receive(timeout: 0) }
try("select timeout") { Ractor.select(Ractor::Port.new, timeout: 0.05) }
try("select ractor timeout") { Ractor.select(Ractor.new { Ractor.receive }, timeout: 0.01) }
try("receive bad timeout") { Ractor.receive(timeout: -1) }
try("receive str timeout") { Ractor.receive(timeout: "1") }
try("receive nil timeout") { Ractor.current.send(5); Ractor.receive(timeout: nil) }
try("waiting message beats timeout") { q = Ractor::Port.new; q << :here; q.receive(timeout: 0) }
inner = Ractor.new { [Ractor.current.default_port.inspect, Ractor::Port.new.inspect] }
try("inner ports") { inner.value.map { |s| s.sub(/to:#\d+/, "to:#N") } }
p Ractor::Port.new
