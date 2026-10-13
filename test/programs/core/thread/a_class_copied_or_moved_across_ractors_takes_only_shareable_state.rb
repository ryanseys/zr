# A copy of a class or module that another ractor made belongs to the
# copying ractor, so its constants, instance variables and class
# variables, and its singleton class's, must be shareable. An object that
# a ractor moves takes its singleton class with it: the receiver owns
# that class, so it may hold only shareable values too.
Warning[:experimental] = false

def try(label)
  puts "#{label}: #{yield.inspect}"
rescue Ractor::RemoteError => e
  puts "#{label}: #{e.cause.class}: #{e.cause.message}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

class Plain
  NAME = "plain".freeze
  def hi = :hi
end

class WithConst
  LIST = []
end

class WithIvar
  @list = []
end

class WithCvar
  @@list = []
end

class WithMetaConst
  class << self
    LIST = []
  end
end

class WithMetaIvar
  class << self
    @list = []
  end
end

module ModWithConst
  LIST = []
end

class ShareableState
  LIST = [1, 2].freeze
  @name = "frozen".freeze
  @@count = 3
end

# The ractor answers with its error, so no thread reports it.
def copy_in_ractor(klass, how)
  Ractor.new(klass, how) do |k, m|
    k.public_send(m).name.inspect
  rescue Ractor::IsolationError => e
    "#{e.class}: #{e.message}"
  end.value
end

try("clone plain") { copy_in_ractor(Plain, :clone) }
try("dup plain") { copy_in_ractor(Plain, :dup) }
try("clone const") { copy_in_ractor(WithConst, :clone) }
try("dup const") { copy_in_ractor(WithConst, :dup) }
try("clone ivar") { copy_in_ractor(WithIvar, :clone) }
try("clone cvar") { copy_in_ractor(WithCvar, :clone) }
try("clone meta const") { copy_in_ractor(WithMetaConst, :clone) }
try("clone meta ivar") { copy_in_ractor(WithMetaIvar, :clone) }
try("dup module const") { copy_in_ractor(ModWithConst, :dup) }
try("clone shareable state") { copy_in_ractor(ShareableState, :clone) }
try("main clones") { [WithConst.clone.name, WithIvar.dup.name] }

# The ractor owns its copy, so it may change it.
try("copy is owned") do
  Ractor.new(Plain) do |k|
    copy = k.dup
    copy.define_method(:bye) { :bye }
    copy.const_set(:EXTRA, [])
    [copy.new.hi, copy.new.bye, copy::EXTRA]
  end.value
end

# A ractor's own class copies whatever it holds.
try("own class") do
  Ractor.new do
    k = Class.new { const_set(:LIST, []) }
    k.instance_variable_set(:@list, [])
    k.dup.const_get(:LIST)
  end.value
end

def move_to_ractor(obj)
  r = Ractor.new { Ractor.receive.then { |o| [o.class, o.singleton_methods.sort] } }
  r.send(obj, move: true)
  r.value
end

plain = Object.new
def plain.hi = :hi
try("move singleton methods") { move_to_ractor(plain) }

ivar = Object.new
ivar.singleton_class.instance_variable_set(:@list, [])
try("move singleton ivar") { move_to_ractor(ivar) }
try("sender keeps it") { ivar.singleton_class.instance_variable_get(:@list) }

const = Object.new
const.singleton_class.const_set(:LIST, [])
try("move singleton const") { move_to_ractor(const) }

cvar = Object.new
cvar.singleton_class.class_variable_set(:@@list, [])
try("move singleton cvar") { move_to_ractor(cvar) }

meta = Object.new
meta.singleton_class.singleton_class.instance_variable_set(:@list, [])
try("move meta singleton") { move_to_ractor(meta) }

shareable = Object.new
shareable.singleton_class.const_set(:NAME, "ok".freeze)
shareable.singleton_class.instance_variable_set(:@n, 1)
try("move shareable singleton") { move_to_ractor(shareable) }

nested = [Object.new.tap { |o| o.singleton_class.instance_variable_set(:@list, []) }]
try("move nested singleton") { move_to_ractor(nested) }
try("nested sender keeps it") { nested.size }

# The receiver owns the moved object's singleton class.
owned = Object.new
def owned.hi = :hi
try("receiver owns the singleton") do
  r = Ractor.new do
    o = Ractor.receive
    o.define_singleton_method(:bye) { :bye }
    o.singleton_class.const_set(:MORE, [])
    [o.hi, o.bye, o.singleton_class::MORE]
  end
  r.send(owned, move: true)
  r.value
end
