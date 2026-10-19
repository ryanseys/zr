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

require "optparse"; require "logger"; require "forwardable"; require "delegate"; require "singleton"; require "observer" rescue nil
require "timeout"; require "monitor"; require "benchmark"; require "weakref"; require "English"; require "tsort"; require "ipaddr"; require "digest"; require "zlib"; require "bigdecimal"; require "bigdecimal/util"
t("optparse") { o = {}; p = OptionParser.new { |op| op.on("-v", "--[no-]verbose"); op.on("-n NUM", Integer); op.on("--list=A,B", Array) }; r = p.parse(%w[-v -n 3 --list x,y rest], into: o); [o, r] }
t("optparse err") { OptionParser.new { _1.on("-n NUM", Integer) }.parse(%w[-n x]) }
t("optparse help") { OptionParser.new { |op| op.banner = "Usage: x"; op.on("-a", "--all", "Show all") }.help }
t("optparse missing") { OptionParser.new { _1.on("-n NUM") }.parse(%w[-n]) }
t("logger") { io = StringIO.new; l = Logger.new(io, progname: "p"); l.formatter = proc { |s, _, pn, m| "#{s}:#{pn}:#{m}\n" }; l.info("i"); l.debug("d"); l.level = :warn; l.info("x"); l.error { "e" }; io.string }
t("forwardable") { c = Class.new { extend Forwardable; def_delegators :@a, :size, :first; def_delegator :@a, :last, :final; def initialize = @a = [1, 2] }; o = c.new; [o.size, o.first, o.final] }
t("delegate") { d = SimpleDelegator.new([1]); d << 2; [d.size, d.__getobj__, d.is_a?(Array), d == [1, 2], DelegateClass(Array).instance_method(:size).owner.class] }
t("singleton") { c = Class.new { include Singleton }; [c.instance.equal?(c.instance), (c.new rescue $!.class)] }
t("timeout") { Timeout.timeout(0.05) { sleep 1 } }
t("timeout ok") { Timeout.timeout(1) { :ok } }
t("monitor") { m = Monitor.new; m.synchronize { m.synchronize { m.mon_locked? } } }
t("benchmark") { Benchmark.measure { 1 + 1 }.class }
t("weakref") { w = WeakRef.new(+"x"); [w.weakref_alive?, w.size] }
t("English") { "ab" =~ /b/; [$PREMATCH, $MATCH, $PROGRAM_NAME.class] }
t("tsort") { h = { 1 => [2, 3], 2 => [3], 3 => [], 4 => [1] }; TSort.tsort(h.method(:each_key), ->(n, &b) { h[n].each(&b) }) }
t("ipaddr") { [IPAddr.new("192.168.1.0/24").include?(IPAddr.new("192.168.1.9")), IPAddr.new("::1").ipv6?, IPAddr.new("10.0.0.1").to_i, IPAddr.new("192.168.1.7/24").to_s, IPAddr.new("1.2.3.4").reverse] }
t("digest") { [Digest::MD5.hexdigest("a"), Digest::SHA256.hexdigest("")[0, 16], Digest::SHA1.base64digest("x"), Digest::SHA512.new.update("a").update("b").hexdigest[0, 8]] }
t("zlib") { z = Zlib::Deflate.deflate("a" * 100); [z.size, Zlib::Inflate.inflate(z).size, Zlib.crc32("abc"), Zlib.adler32("abc"), Zlib.gunzip(Zlib.gzip("q"))] }
t("bigdecimal") { [BigDecimal("1.1") + BigDecimal("2.2"), (BigDecimal("1") / 3).round(5).to_s, BigDecimal("0.1").to_f, "3.14".to_d.class, BigDecimal("1e-2").to_s("F"), BigDecimal("123.456").truncate(1).to_s] }
t("comparable") { c = Class.new { include Comparable; attr_reader :v; def initialize(v); @v = v; end; def <=>(o) = v <=> o.v }; [c.new(1) < c.new(2), c.new(5).clamp(c.new(1), c.new(3)).v, [c.new(2), c.new(1)].max.v] }
t("exceptions") { begin; Integer("x"); rescue => e; [e.class, e.message, e.full_message(highlight: false).lines.first.sub(/^.*?: /, "")]; end }
t("exc detail") { begin; nil.foo; rescue NoMethodError => e; [e.name, e.receiver, e.message]; end }
t("frozen") { begin; "a".freeze << "b"; rescue => e; [e.class, e.message, e.receiver]; end }
t("keyerror") { begin; { a: 1 }.fetch(:b); rescue KeyError => e; [e.message, e.key, e.receiver]; end }
t("catch") { catch(:x) { 10.times { |i| throw :x, i if i == 3 }; :no } }
t("method") { m = 1.method(:+); [m.arity, m.owner, m.call(2), m.unbind.bind(3).call(1), [1, 2].map(&10.method(:*))] }
t("proc") { pr = proc { |a, (b, c), *d, e: 1, &f| [a, b, c, d, e] }; [pr.arity, pr.parameters, pr.call(1, [2, 3], 4, 5), pr.curry.class, lambda { |x| x }.lambda?] }
t("refine") { m = Module.new { refine(Integer) { def double = self * 2 } }; Module.new { using m; @r = 5.double }.instance_variable_get(:@r) }
t("object") { o = Object.new; def o.hi = 1; [o.singleton_methods, o.respond_to?(:hi), o.frozen?, o.dup.respond_to?(:hi), o.clone.respond_to?(:hi)] }
t("pattern") { case { name: "x", age: 3, tags: [1, 2] }; in { name: String => n, age: Integer => a, tags: [*, 2] } then [n, a] end }
t("pattern find") { case [1, "a", :b, 2]; in [*, Symbol => s, *post] then [s, post] end }
t("pattern err") { case 5; in String then 1 end }
