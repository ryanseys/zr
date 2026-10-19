# A probe of many methods, each line one call and its answer or its error,
# compared with ruby's.
def t(label)
  r = begin
    yield.inspect
  rescue Exception => e
    "#{e.class}: #{e.message}"
  end
  puts "#{label}: #{r}"
end

t("marshal") { o = [1, "s", :sym, 2.5, nil, { a: [1] }, 1 << 70, Struct.new(:a).new(1).to_a, Time.at(0, 5, :nsec).utc]; Marshal.load(Marshal.dump(o)) == o }
t("marshal bytes") { Marshal.dump([1, "a", :b, 1.5, { c: nil }]).bytes.sum }
t("marshal err") { Marshal.load("\x04\x09junk") }
t("marshal proc") { Marshal.dump(proc {}) }
t("enumerator") { e = [1, 2, 3].each; [e.next, e.next, e.peek, e.next, (e.next rescue $!.class), e.size] }
t("enum new") { Enumerator.new { |y| y << 1 << 2; y.yield 3, 4 }.to_a }
t("enum with_index") { %w[a b].each.with_index(1).map { |s, i| "#{i}#{s}" } + [%w[a b].each_with_index.to_a] }
t("enum produce") { Enumerator.produce(1) { _1 * 3 }.take(4) }
t("enum chain") { ([1].each + [2] + (3..4)).to_a }
t("enum product") { Enumerator.product([1, 2], [3]).to_a rescue $!.class }
t("fiber") { f = Fiber.new { |x| y = Fiber.yield(x * 2); y + 1 }; [f.resume(5), f.resume(10), f.alive?] }
t("fiber err") { f = Fiber.new { 1 }; f.resume; f.resume }
t("thread") { q = Queue.new; th = 3.times.map { |i| Thread.new { q << i * i } }; th.each(&:join); Array.new(3) { q.pop }.sort }
t("thread value") { Thread.new { Thread.current[:x] = 1; [Thread.current[:x], Thread.current.name] }.value }
t("thread exc") { Thread.new { Thread.current.report_on_exception = false; raise "boom" }.join }
t("mutex") { m = Mutex.new; c = 0; 4.times.map { Thread.new { 100.times { m.synchronize { c += 1 } } } }.each(&:join); c }
t("cv") { m = Mutex.new; cv = ConditionVariable.new; done = false; th = Thread.new { m.synchronize { cv.wait(m) until done; :woke } }; sleep 0.01; m.synchronize { done = true; cv.signal }; th.value }
t("sized queue") { q = SizedQueue.new(1); q << 1; [q.size, q.max, (q.push(2, true) rescue $!.class), q.pop] }
t("process") { pid = fork { exit! 7 }; Process.wait(pid); [$?.exitstatus, $?.success?, Process.respond_to?(:fork)] }
t("spawn") { r, w = IO.pipe; pid = spawn("echo", "sp", out: w); w.close; Process.wait(pid); r.read }
t("signal") { r = []; old = trap("USR1") { r << :got }; Process.kill("USR1", Process.pid); sleep 0.05; trap("USR1", old); r }
t("at_exit order") { :skip }
t("chilled") { s = "lit"; s << "x"; s }
t("frozen sym") { :a.to_s.frozen? }
t("name error") { begin; undefined_thing; rescue NameError => e; e.message; end }
t("no method msg") { begin; 5.upcase; rescue => e; e.message; end }
t("arg error") { begin; [].first(1, 2); rescue => e; e.message; end }
t("arg error2") { def m1(a, b: 1) = a; begin; m1; rescue => e; e.message; end }
t("kw error") { def m2(a:) = a; begin; m2(b: 1); rescue => e; e.message; end }
t("type error") { begin; 1 + "a"; rescue => e; [e.class, e.message]; end }
t("zero div") { [(1 / 0 rescue $!.message), 1.0 / 0, -1 % 3, -7.divmod(2), 7.fdiv(2), 2**-1, 0**0, 10.0 % 3] }
t("range") { [(1..10).step(3).to_a, (1.0..2.0).step(0.5).to_a, ("a".."e").each_slice(2).to_a, (1..).first(2), (..5).include?(3), (1...10).size, Range.new(1, 3, true).to_a] }
t("comparable clamp") { [5.clamp(1, 3), 5.clamp(..3), 1.5.clamp(2, 3)] }
t("integer") { [100.digits(16), 6.lcm(4), 6.gcd(4), (2**64).to_s(36), Integer("0b101", exception: false), Integer("z", 36), 3.7.to_i, -3.7.truncate, 12.34.floor(1)] }
t("string misc") { ["abc".each_char.to_a, "a,b,,c".split(","), "a,b,,c".split(",", -1), "a b".split, "abc".partition("b"), "aaa".count("a"), "x".ord, "%s" % nil, "ab" * 3, "a".between?("a", "b")] }
t("string bytes") { s = "héllo"; [s.bytesize, s.byteslice(1, 2), s.byteindex("l"), s.unpack1("U*"), s.b.length, s.force_encoding("BINARY").valid_encoding?] }
t("symbol") { [:abc <=> :abd, (:a.to_proc.call("x") rescue $!.class), %i[a b].map(&:to_s), :"foo bar".inspect, :a.size, :"9".inspect] }
t("object_id ints") { [1.object_id, nil.object_id, true.object_id] }
t("freeze") { a = [1].freeze; [a.frozen?, (a << 2 rescue $!.class), a.dup.frozen?, a.clone.frozen?, a.clone(freeze: false).frozen?] }
t("hash default") { h = Hash.new { |hh, k| hh[k] = k * 2 }; h[3]; [h, h.default_proc.arity, Hash.new(5)[1], h.compare_by_identity.compare_by_identity?] }
t("to_s inspect") { [nil.inspect, 1.0.inspect, 1e-10.inspect, -0.0.inspect, "a\tb\e".inspect, "é".inspect, "\xff".inspect, [nil, [true]].to_s, { 1 => "a", b: :c }.inspect] }
t("gc api") { [GC.count.is_a?(Integer), GC.stat.key?(:count), GC.respond_to?(:compact)] }
