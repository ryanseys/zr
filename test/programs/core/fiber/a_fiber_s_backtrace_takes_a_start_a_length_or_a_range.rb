# A fiber's backtrace and backtrace_locations take a start, a length or
# a Range, as a thread's do.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 100]}"
end

f = Fiber.new { 1.tap { 2.tap { Fiber.yield } } }
t("unborn") { [f.backtrace, f.backtrace_locations] }
f.resume
all = f.backtrace
t("all") { all.size >= 3 }
t("start") { [f.backtrace(0) == all, f.backtrace(1) == all.drop(1)] }
t("length") { [f.backtrace(0, 1) == all.take(1), f.backtrace(1, 1) == all[1, 1]] }
t("range") { [f.backtrace(0..1) == all[0..1], f.backtrace(1..) == all[1..], f.backtrace(0...0)] }
t("locations") { [f.backtrace_locations(0, 1).map(&:to_s) == all.take(1), f.backtrace_locations(0..1).map(&:to_s) == all[0..1]] }
f.resume
t("dead") { [f.backtrace, f.backtrace_locations] }
