# What a send copies (ractor.c courier): a String, an Array, a Hash, a
# Struct, a Data, a Range, a Regexp, a MatchData, an Exception (with its
# message, cause and backtrace) and a plain object are copied part by
# part. C data goes only through a dump hook (Time's _dump, Random's
# marshal_dump, Set's compat). Anything else is refused before any copy,
# with the class of the value that was sent. A move takes the plain
# kinds and an IO, keeps a singleton class, and refuses C data by the
# class of the node.
Warning[:experimental] = false
def try(label)
  print label, ": "
  p yield
rescue Exception => e
  puts "#{e.class}: #{e.message}"
end

class WithDump
  def initialize(v) = @v = v
  def marshal_dump = [@v]
  def marshal_load(a) = @v = a.first * 2
  attr_reader :v
end
class WithUnderDump
  def initialize(v) = @v = v
  def _dump(_) = @v.to_s
  def self._load(s) = new(s + "!")
  attr_reader :v
end
Pt = Struct.new(:a)
Dt = Data.define(:a)
class Plain; def initialize = @a = [1]; attr_reader :a; end
r = Ractor.new { loop { Ractor.receive } }
echo = ->(obj) { Ractor.new(obj) { |o| o }.value }
try("proc") { r.send(proc {}) ; :sent }
try("[proc]") { r.send([proc {}]) ; :sent }
try("{a: proc}") { r.send({a: proc {}}) ; :sent }
try("thread") { r.send(Thread.current) ; :sent }
try("mutex") { r.send(Mutex.new) ; :sent }
try("method") { r.send(1.method(:+)) ; :sent }
try("unbound") { r.send(String.instance_method(:size)) ; :sent }
try("enumerator") { r.send([1].each) ; :sent }
try("time") { echo.(Time.at(0).utc) }
try("set") { echo.(Set[1, 2]) }
try("range") { echo.(Range.new(+"a", +"b")) }
try("withdump") { echo.(WithDump.new(3)).v }
try("with_dump") { echo.(WithUnderDump.new("x")).v }
try("struct") { echo.(Pt.new([1])) }
try("data") { echo.(Dt.new(a: [1])) }
try("exception") { e = echo.(RuntimeError.new("boom")); [e.class, e.message] }
try("plain") { echo.(Plain.new).a }
try("singleton") { o = Object.new; def o.x = 1; echo.(o).x }
try("extended") { o = Object.new; o.extend(Comparable); echo.(o).singleton_class.include?(Comparable) }
try("io") { r.send($stdout) ; :sent }
try("file") { f = File.open(__FILE__); r.send(f); :sent }
try("binding") { r.send(binding) ; :sent }
try("random") { echo.(Random.new(1)).class }
try("string sub") { c = Class.new(String); echo.(c.new("x")).class == c }
try("float") { echo.(1.5) }
try("bigint") { echo.(2**70) }
try("rational") { echo.(Rational(1, 3)) }
try("matchdata") { m = echo.(/b/.match(+"abc")); [m.class, m[0], m.pre_match] }
try("object") { echo.(Object.new).class }
try("basicobject") { echo.(BasicObject.new).__id__.class }
try("weakmap") { r.send(ObjectSpace::WeakMap.new); :sent }
try("hash default proc") { h = Hash.new { 1 }; r.send(h); :sent }
try("hash cbi") { h = {}.compare_by_identity; h[+"a"] = 1; echo.(h).compare_by_identity? }
try("nested proc in ivar") { o = Plain.new; o.instance_variable_set(:@p, proc {}); r.send(o); :sent }
try("deep cycle") { a = []; a << a; b = echo.(a); b[0].equal?(b) }
try("frozen string") { s = "x".freeze; echo.(s).equal?(s) }
try("class") { echo.(String) }
# moves
mv = ->(obj) { Ractor.new { Ractor.receive }.tap { |x| x.send(obj, move: true) }.value }
try("move proc") { mv.(proc {}) }
try("move [proc]") { mv.([proc {}]) }
try("move thread") { mv.(Thread.current) }
try("move method") { mv.(1.method(:+)) }
try("move time") { mv.(Time.at(0).utc) }
try("move withdump") { mv.(WithDump.new(3)).v }
try("move plain") { mv.(Plain.new).a }
try("move struct") { mv.(Pt.new([1])) }
try("move exception") { mv.(RuntimeError.new("x")).message }
try("move set") { mv.(Set[1]) }
try("move io") { mv.(File.open(__FILE__)).class }
try("move mutex") { mv.(Mutex.new) }
try("move enumerator") { mv.([1].each) }
try("move matchdata") { mv.(/b/.match(+"abc"))[0] }
try("move range") { mv.(Range.new(+"a", +"b")) }
try("move singleton") { o = Object.new; def o.x = 1; mv.(o).x }
try("bt") { e = begin; raise "x"; rescue => e; e; end; c = echo.(e); [c.backtrace == e.backtrace, c.backtrace_locations&.size == e.backtrace_locations.size, c.cause] }
try("cause") { e = begin; begin; raise "a"; rescue; raise "b"; end; rescue => e; e; end; c = echo.(e); [c.message, c.cause&.message] }
try("stat") { echo.(File::Stat.new(".")).class }
try("yielder") { Enumerator.new { |y| echo.(y) }.next }
try("ivar on string") { s = +"x"; s.instance_variable_set(:@a, [1]); echo.(s).instance_variable_get(:@a) }
try("frozen dup") { a = [+"x"].freeze; b = echo.(a); [b.frozen?, b[0].frozen?] }
try("default value") { h = Hash.new([1]); echo.(h).default }
try("regexp sub") { c = Class.new(Regexp); r = echo.(c.new("a")); [r.class == c, r.frozen?, r.source] }
try("singleton ext move") { o = Object.new; o.extend(Comparable); x = Ractor.new { Ractor.receive }; x.send(o, move: true); x.value.singleton_class.include?(Comparable) }
try("time in an array on move") { x = Ractor.new { Ractor.receive }; x.send([1, Time.now], move: true); x.value }
try("struct with proc") { echo.(Pt.new(proc {})) }
try("move hash dproc") { h = Hash.new { 1 }; x = Ractor.new { Ractor.receive }; x.send(h, move: true); :ok }
try("copy is a new object") { s = +"x"; c = echo.(s); [c == s, c.equal?(s), c.object_id == s.object_id] }
try("range copy") { r = Range.new(+"a", +"c"); c = echo.(r); [c, c.frozen?, c.begin.equal?(r.begin), c.to_a] }
try("struct copy keeps its values apart") { s = Pt.new(+"v"); c = echo.(s); c.a << "!"; [s.a, c.a] }
try("set copy") { s = Set[+"a"].compare_by_identity; c = echo.(s); [c.class, c.compare_by_identity?, c == s] }
try("time copy") { t = Time.at(1, 500, :millisecond).utc; c = echo.(t); [c == t, c.equal?(t), c.utc?] }
try("arg uncopyable") { Ractor.new(proc {}) { 1 } }
try("arg in array") { Ractor.new([1, Thread.current]) { 1 } }
try("moved file works") { f = File.open(__FILE__); x = Ractor.new { Ractor.receive.gets }; x.send(f, move: true); x.value.start_with?("#") }
