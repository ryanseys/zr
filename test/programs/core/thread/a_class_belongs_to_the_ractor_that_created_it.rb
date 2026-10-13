# Class ownership: only the ractor that created a class or module
# changes it (methods, aliases, constants, includes, its own instance
# variables, its class variables, freeze, set_temporary_name, refine).
# Another ractor reads it, but no unshareable value in it. A ractor has
# full use of its own classes, unshareable constants included. A
# singleton class is its object's; a shareable object's is the main
# ractor's.
Warning[:experimental] = false
Thread.report_on_exception = false
def try(label)
  print label, ": "
  p yield
rescue Ractor::RemoteError => e
  puts "#{e.cause.class}: #{e.cause.message.gsub(/0x\h+/, "0xX")}"
rescue => e
  puts "#{e.class}: #{e.message.gsub(/0x\h+/, "0xX")}"
end

class Main
  NAMES = ["a"]
  FROZEN = "f".freeze
  @list = [1]
  @@count = [0]
  @@shared = 1
  def self.list = @list
  def self.count = @@count
  def self.shared = @@shared
  def self.bump = @@shared += 1
  def m = 1
end
module M; def mm = 2; end

try("define a method") { Ractor.new { Main.define_method(:x) { 1 } }.value }
try("def in a class body") { Ractor.new { class Main; def y = 1; end }.value }
try("alias") { Ractor.new { Main.alias_method(:m2, :m) }.value }
try("undef") { Ractor.new { Main.send(:undef_method, :m) }.value }
try("remove_method") { Ractor.new { Main.send(:remove_method, :m) }.value }
try("private") { Ractor.new { Main.send(:private, :m) }.value }
try("include") { Ractor.new { Main.include(Comparable) }.value }
try("prepend") { Ractor.new { Main.prepend(Comparable) }.value }
try("const_set") { Ractor.new { Main.const_set(:NEW, 1) }.value }
try("const literal") { Ractor.new { Main::NEW2 = 1 }.value }
try("remove_const") { Ractor.new { Main.send(:remove_const, :FROZEN) }.value }
try("private_constant") { Ractor.new { Main.private_constant(:FROZEN) }.value }
try("autoload") { Ractor.new { Main.autoload(:Later, "later") }.value }
try("read shareable const") { Ractor.new { Main::FROZEN }.value }
try("read unshareable const") { Ractor.new { Main::NAMES }.value }
try("const_get unshareable") { Ractor.new { Main.const_get(:NAMES) }.value }
try("class ivar read") { Ractor.new { Main.list }.value }
try("class ivar write") { Ractor.new { Main.instance_variable_set(:@list, 1) }.value }
try("cvar read unshareable") { Ractor.new { Main.count }.value }
try("cvar read shareable") { Ractor.new { Main.shared }.value }
try("cvar write") { Ractor.new { Main.bump }.value }
try("class_variable_set") { Ractor.new { Main.class_variable_set(:@@shared, 3) }.value }
try("class_variable_get unshareable") { Ractor.new { Main.class_variable_get(:@@count) }.value }
try("remove_class_variable") { Ractor.new { Main.send(:remove_class_variable, :@@shared) }.value }
try("freeze") { Ractor.new { Main.freeze }.value }
try("set_temporary_name") { Ractor.new { Class.new.tap { |c| c.name }; Main.set_temporary_name("x") rescue $!.class }.value }
try("refine") { Ractor.new { M.send(:refine, String) { def z = 1 } }.value }
try("singleton of Ractor.main") { Ractor.new { Ractor.main.define_singleton_method(:zzz) { :sub } }.value }
try("singleton of a class") { Ractor.new { def Main.zz = 1 }.value }
try("include into own class") { Ractor.new { c = Class.new; c.include(M); c.new.mm }.value }

own = Ractor.new do
  klass = Class.new do
    const_set(:LIST, [1, 2])
    @state = [3]
    class_variable_set(:@@seen, [4])
    def self.state = @state
    def self.seen = class_variable_get(:@@seen)
  end
  klass.define_method(:hi) { :hi }
  klass.alias_method(:hello, :hi)
  klass.const_set(:MORE, +"more")
  [klass, klass::LIST, klass.state, klass.seen, klass.new.hello, klass::MORE]
end
klass, *rest = own.value
try("own class from inside") { rest }
try("main reads its unshareable const") { klass::LIST }
try("main reads its ivar") { klass.state }
try("main reads its cvar") { klass.seen }
try("main defines a method on it") { klass.define_method(:nope) { 1 } }
try("main sets a const on it") { klass.const_set(:X, 1) }
try("main freezes it") { klass.freeze }
try("main calls its method") { klass.new.hi }
try("main reads its shareable const") { klass.const_get(:MORE).frozen? rescue $!.class }

try("a thread in a ractor is the ractor's") do
  Ractor.new { Thread.new { [Ractor.current == Ractor.main, Ractor.main?] }.value }.value
end
try("a fiber in a ractor is the ractor's") do
  Ractor.new { Fiber.new { Ractor.main? }.resume }.value
end
try("main still owns its classes") { class Main; def later = 1; end; Main.new.later }
try("main sets an unshareable const") { Main.const_set(:LATE, [1]); Main::LATE }
