Warning[:experimental] = false

def try(label)
  value = yield
  puts "#{label}: #{value.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message.lines.first.chomp.gsub(/0x\h+/, "0xX").gsub(/fd \d+/, "fd N")}"
end

def share(label, &) = try(label) { Ractor.shareable?(Ractor.make_shareable(yield)) }

# Procs that the core makes cannot be made shareable.
share("Hash#to_proc") { Hash.new { 1 }.to_proc }
share("frozen Hash#to_proc") { { a: 1 }.freeze.to_proc }
share("Method#to_proc") { 1.method(:+).to_proc }
share("Kernel#method to_proc") { method(:puts).to_proc }
share("curry") { proc { |a, b| }.curry }
share("lambda curry") { nil.instance_eval { lambda { |a, b| }.curry } }
share("Symbol#to_proc") { :upcase.to_proc }
share("proc with an unshareable self") { Object.new.instance_eval { proc { 1 } } }
share("nil self proc") { nil.instance_eval { proc { 1 } } }

# A Method is shareable when its receiver is; make_shareable leaves the
# receiver as it is.
share("Integer method") { 1.method(:+) }
share("frozen String method") { "x".freeze.method(:to_s) }
share("String method") { (+"").method(:to_s) }
share("Method in an Array") { [(+"").method(:to_s)] }
share("UnboundMethod") { String.instance_method(:to_s) }
try("make_shareable freezes the Method") { Ractor.make_shareable(1.method(:+)).frozen? }
try("the receiver stays unfrozen") do
  receiver = Object.new
  m = receiver.method(:to_s)
  Ractor.make_shareable(m)
rescue Ractor::Error
  [receiver.frozen?, m.frozen?]
end
share("a frozen Method") { 1.method(:+).freeze }
try("shareable? of a frozen Method") { Ractor.shareable?(1.method(:+).freeze) }
try("shareable? of an unfrozen Method") { Ractor.shareable?(1.method(:+)) }
try("shareable? of a Method with an unshareable receiver") { Ractor.shareable?((+"x").method(:to_s).freeze) }

# The message shows the object's inspect, not a to_s the program gave it.
x = (+"").instance_exec { method(:to_s) }
def x.to_s = raise("to_s should not run")
share("singleton to_s") { x }

# Objects that CRuby keeps as C data refuse.
share("Thread") { Thread.current }
share("Mutex") { Mutex.new }
share("Queue") { Queue.new }
share("SizedQueue") { SizedQueue.new(1) }
share("ConditionVariable") { ConditionVariable.new }
share("ThreadGroup") { ThreadGroup.new }
share("Enumerator") { [1].each }
share("Lazy") { [1].lazy }
share("Chain") { [1].each + [2] }
share("ArithmeticSequence") { 1.step(10, 2) }
try("Binding refuses") { Ractor.make_shareable(binding) && :shared }
share("Random") { Random.new(1) }
share("WeakMap") { ObjectSpace::WeakMap.new }
share("TracePoint") { TracePoint.new(:line) {} }
share("IO::Buffer") { IO::Buffer.new(4) }
share("Dir") { Dir.new(".") }
share("Encoding::Converter") { Encoding::Converter.new("UTF-8", "EUC-JP") }

# These are shareable once frozen.
share("Time") { Time.at(0) }
share("IO") { IO.pipe[0] }
share("Set") { Set[[1]] }
share("Port") { Ractor::Port.new }
share("Regexp") { Regexp.new("a") }
share("MatchData") { "ab".match(/a/) }
share("Complex") { Complex(1, 2) }
share("Exception") { RuntimeError.new("x") }
share("Struct") { Struct.new(:a).new([1]) }
share("Data") { Data.define(:a).new([1]) }
