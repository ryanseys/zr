def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end

t(:fork_threads) { th = Thread.new { sleep }; r, w = IO.pipe; pid = fork { w.write(Thread.list.size.to_s); exit!(0) }; w.close; Process.wait(pid); th.kill; r.read }
t(:fork_mutex) { m = Mutex.new; m.lock; pid = fork { exit!(m.locked? ? 1 : 2) }; Process.wait(pid); m.unlock; $?.exitstatus }
t(:epipe) { r, w = IO.pipe; r.close; w.write("x") }
t(:sigpipe_default) { Signal.trap("PIPE", "SYSTEM_DEFAULT") == "SYSTEM_DEFAULT" || :set }
t(:thread_stop_wakeup) { th = Thread.new { Thread.stop; :woke }; sleep 0.01 until th.status == "sleep"; th.wakeup; th.value }
t(:thread_run) { th = Thread.new { Thread.stop; 5 }; sleep 0.01 until th.stop?; th.run; th.value }
t(:thread_raise_sleep) { th = Thread.new { begin; sleep; rescue => e; e.message; end }; sleep 0.01 until th.status == "sleep"; th.raise("wake"); th.value }
t(:thread_kill_ensure) { r = []; th = Thread.new { begin; sleep; ensure; r << :ensured; end }; sleep 0.01 until th.status == "sleep"; th.kill; th.join; r }
t(:thread_exit_value) { Thread.new { Thread.exit; 1 }.value }
t(:thread_join_timeout) { Thread.new { sleep 1 }.join(0.01) }
t(:thread_variable_fiber) { Thread.current.thread_variable_set(:tv, 1); Fiber.new { [Thread.current.thread_variable_get(:tv), Thread.current[:fl]] }.resume }
t(:fiber_local_vs_thread) { Thread.current[:fl] = 1; Fiber.new { Thread.current[:fl] }.resume }
t(:mutex_owned) { m = Mutex.new; m.synchronize { [m.owned?, Thread.new { m.owned? }.value] } }
t(:mutex_sleep) { m = Mutex.new; m.synchronize { m.sleep(0.01).class } }
t(:queue_num_waiting) { q = Queue.new; th = Thread.new { q.pop }; sleep 0.01 until th.status == "sleep"; n = q.num_waiting; q << 1; th.join; n }
t(:cv_broadcast) { m = Mutex.new; cv = ConditionVariable.new; n = 0; waiting = 0; ths = 3.times.map { Thread.new { m.synchronize { waiting += 1; cv.wait(m); n += 1 } } }; sleep 0.01 until m.synchronize { waiting } == 3; m.synchronize { cv.broadcast }; ths.each(&:join); n }
t(:report_on_exception_default) { Thread.report_on_exception }
t(:thread_group_add) { g = ThreadGroup.new; gate = Queue.new; th = Thread.new { gate.pop }; g.add(th); [g.list.size, th.group == g].tap { gate << 1; th.join } }
t(:pending_interrupt) { Thread.pending_interrupt? }
t(:sleep_forever_interrupt) { th = Thread.new { sleep }; sleep 0.01 until th.status == "sleep"; th.wakeup; th.join(1).class }
t(:marshal_compat) { File.binwrite("m.bin", Marshal.dump([1, "s", :sym, 2.5, 2**80, {k: [nil]}, Time.at(0, 123456789, :nsec).utc, 1..2, Struct.new(:a).new(1).to_a, "é".encode("UTF-16LE")])); IO.popen(["ruby", "-e", "p Marshal.load(File.binread('m.bin'))"], &:read) }
t(:marshal_user_class) { Object.const_set(:MUC, Class.new { def initialize = (@a = 1; @b = "x") }); s = Marshal.dump(MUC.new); [s.bytesize, Marshal.load(s).instance_variables] }
t(:marshal_extended) { o = Object.new.extend(Comparable); Marshal.load(Marshal.dump(o)).singleton_class.include?(Comparable) }
t(:marshal_ivar_string) { s = +"str"; s.instance_variable_set(:@iv, 1); Marshal.load(Marshal.dump(s)).instance_variable_get(:@iv) }
t(:marshal_depth) { Marshal.dump([[[1]]], 1) }
t(:marshal_io) { Marshal.dump($stdout) }
t(:marshal_singleton) { o = Object.new; def o.x = 1; Marshal.dump(o) }
t(:marshal_load_proc) { Marshal.load(Marshal.dump([1, "a"]), ->(x) { x.is_a?(Integer) ? x + 1 : x }) }
t(:marshal_float_special) { [Float::NAN, -0.0, Float::INFINITY].map { Marshal.load(Marshal.dump(_1)).to_s } }
t(:objectspace_weakmap_gc) { m = ObjectSpace::WeakMap.new; 100.times { m[Object.new] = 1 }; GC.start; m.size <= 100 }
