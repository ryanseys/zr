# Classes and refinements made and dropped in a loop keep the memory of
# the process flat (test_module.rb, test_complemented_method_entry_memory_leak):
# each class's methods go with it. A method that another class took from
# a dropped module, an UnboundMethod and an exception's backtrace keep
# what they show.
def rss_kb
  status = "/proc/self/status"
  return File.foreach(status).find { |line| line.start_with?("VmRSS:") }.split[1].to_i if File.exist?(status)

  `ps -o rss= -p #{$$}`.to_i
end

code = proc do
  $c = Class.new do
    def foo; end
  end
  $m = Module.new do
    refine $c do
      def foo; end
    end
  end
  Class.new do
    using $m
    def initialize
      o = $c.new
      o.method(:foo).unbind
    end
  end.new
  Class.new { define_method(:bar) { } }
  o = Object.new
  def o.baz; end
end
2_000.times(&code)
GC.start
before = rss_kb
60_000.times(&code)
GC.start
p rss_kb - before < 8_192

taker = Class.new
unbound = nil
errors = []
5.times do |i|
  source = Module.new do
    def shown = "def #{self.class.ancestors[1].class}"
    define_method(:made) { "define_method #{i}" }
    def fail = raise("from a dropped module")
  end
  sub = Class.new { include source }
  taker.define_method(:"made#{i}", source.instance_method(:made))
  unbound = source.instance_method(:shown) if i == 2
  errors << (sub.new.fail rescue $!)
end
GC.start
GC.start
p taker.new.made3
p unbound.name, unbound.owner.instance_method(:shown).source_location&.last
puts errors.map { |e| e.backtrace.first[/'.*'/] }.uniq
p taker.instance_method(:made4).bind(taker.new).call
