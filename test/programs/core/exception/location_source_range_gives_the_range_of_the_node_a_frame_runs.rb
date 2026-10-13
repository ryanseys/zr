# Thread::Backtrace::Location#source_range (ruby 4.1) gives the range of
# the node that the frame runs: the call, super or yield, the call that a
# C frame runs under, or the first statement of a body that a frame has
# just entered (a TracePoint :call). Code that an eval compiled raises
# ArgumentError, as ruby cannot read it again. Locations of other threads
# and fibers, of errors and of required files have their ranges too.
$stdout.sync = true
require_relative "location_range_lib/lib2"
def show(label, l)
  r = l.source_range
  p [label, l.lineno, l.label, File.basename(r.path), r.absolute_path && r.absolute_path == File.realpath(r.path), r.start_line, r.start_column, r.end_line, r.end_column]
rescue => e
  p [label, e.class, e.message.sub(/\/\S+\//, "")]
end
def here = caller_locations(1, 1)[0]
show :plain, here
x = [1, 2].map { |v| here }.first
show :in_block, x
show :assign, (y = here)
show :multi, here(
)
def deep
  raise "boom"
end
begin
  deep
rescue => e
  e.backtrace_locations.each_with_index { |l, i| show :"bt#{i}", l }
end
show :self0, caller_locations(0, 1)[0]
show :ev, eval("here")
show :ev_file, eval("here", binding, __FILE__, 30)
show :c_frame, ([1].map { caller_locations(1, 1)[0] }.first)
o = Object.new
def o.method_missing(n, *) = caller_locations(1, 1)[0]
show :mm, o.anything
show :op, (def +(o) = caller_locations(1, 1)[0]; self + 1)
show :index, (def [](i) = caller_locations(1, 1)[0]; self[0])
show :attr_asgn, (def zz=(v); $zz = caller_locations(1, 1)[0]; end; self.zz = 1; $zz)
show :safe, (nil&.foo; here)
show :yield, (def yy = yield; yy { here })
show :super, (class A; def s = caller_locations(1,1)[0]; end; class B < A; def s = super; end; B.new.s)
show :str, "#{here.then { |l| l }}".then { here }
show :lib, Lib2.where
begin
  Lib2.fail!
rescue => e
  e.backtrace_locations.first(3).each_with_index { |l, i| show :"fail#{i}", l }
end
show :thread_cur, Thread.current.backtrace_locations(0, 1)[0]
t = Thread.new { Thread.stop; 1 }
Thread.pass until t.status == "sleep"
show :thread_other, t.backtrace_locations[0]
t.run; t.join
show :times, 1.times.map { caller_locations(1, 1)[0] }.first
f = Fiber.new { Fiber.yield caller_locations(0, 1)[0] }
show :fiber, f.resume
show :instance_eval, Object.new.instance_eval { caller_locations(0, 1)[0] }
show :str_eval, Object.new.instance_eval("caller_locations(0, 1)[0]")
show :define_method, (define_method(:dmx) { caller_locations(0, 1)[0] }; dmx)
show :tp, (r = nil; tp = TracePoint.new(:call) { |x| r ||= caller_locations(1, 1)[0] }; def tpm = 1; tp.enable { tpm }; r)
show :ensure, (begin; ensure; $ens = caller_locations(0, 1)[0]; end; $ens)
