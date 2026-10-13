# Thread::Backtrace::Location#source_range (ruby 4.1) gives the range of
# the node where the frame stands when it raises: a call, a constant read
# or write, an operator assignment of any kind of variable, a target of a
# multiple assignment, the conversion of a value to destructure or splat,
# a pattern, a keyword hash, a class body, or the def, block or lambda
# whose arguments do not fit. #syntax_tree gives the same node. Each case
# loads a file, as the range comes from a read of the file again.
$stdout.sync = true
DIR = File.join(Dir.pwd, "tmp_location_source_range_#{$$}")
Dir.mkdir(DIR)
PATH = File.join(DIR, "case.rb")

def range_of(source, frame = 0)
  File.binwrite(PATH, source)
  error = begin
    load PATH
    nil
  rescue Exception => e
    e
  end
  return "no error" unless error

  location = error.backtrace_locations.reject { _1.path.start_with?("<internal:") }.fetch(frame)
  r = location.source_range
  node = location.syntax_tree&.class&.name&.delete_prefix("Ruby::Prism::")
  "#{error.class} #{location.lineno} #{[r.start_line, r.start_column, r.end_line, r.end_column]} #{node}"
rescue Exception => e
  "#{e.class}: #{e.message}"
end

CASES = {
  "safe call" => "1&.foo(42)\n",
  "bare constant" => "SourceRangeNotDefined\n",
  "qualified constant" => "Object::\n  SourceRangeNotDefined\n",
  "top constant" => "::SourceRangeNotDefined\n",
  "path op-assign" => "n = Module.new\nn.const_set(:Nil, nil)\nn::Nil += 1\n",
  "path op-assign unset" => "n = Module.new\nn::NotDefined += 1\n",
  "top path op-assign" => "::SourceRangeNotDefined += 1\n",
  "constant op-assign" => "SourceRangeNotDefined += 1\n",
  "constant op-assign operator" => "class << Object.new\n  Nil = nil\n  Nil += 1\nend\n",
  "constant op-assign value" => "class << Object.new\n  One = 1\n  One += nil\nend\n",
  "constant and-assign" => "SourceRangeNotDefined &&= 1\n",
  "top path and-assign" => "::SourceRangeNotDefined &&= 1\n",
  "nil scope op-assign" => "n = nil\nn::NotDefined += 1\n",
  "nil scope or-assign" => "n = nil\nn::NotDefined ||= 1\n",
  "nil scope and-assign" => "n = nil\nn::NotDefined &&= 1\n",
  "nil scope write" => "n = nil\nn::NotDefined = 1\n",
  "unset scope of a write" => "SourceRangeNotDefined::Nested = 1\n",
  "ivar op-assign" => "@source_range_value += 1\n",
  "cvar op-assign unset" => "class SourceRangeCvars\n  @@not_defined += 1\nend\n",
  "cvar op-assign operator" => "class SourceRangeCvars\n  @@nil = nil\n  @@nil += 1\nend\n",
  "cvar and-assign unset" => "class SourceRangeCvars\n  @@unset_too &&= 1\nend\n",
  "gvar op-assign" => "$source_range_gvar += 1\n",
  "attribute target" => "v = nil\nv.foo, other = 1, 2\n",
  "splat attribute target" => "v = nil\n*v.foo = 1, 2\n",
  "index target" => "v = nil\nv[0], other = 1, 2\n",
  "constant path target" => "n = nil\nn::NotDefined, other = 1, 2\n",
  "for target" => "v = nil\nfor v.foo in [1]\nend\n",
  "rescue target" => "v = nil\nbegin\n  raise \"error\"\nrescue => v.foo\nend\n",
  "hash pattern" => "v = Object.new\ndef v.deconstruct_keys(keys) = nil\ncase v\nin key:\nend\n",
  "hash pattern rest" => "v = Object.new\ndef v.deconstruct_keys(keys) = nil\ncase v\nin **rest\nend\n",
  "array pattern" => "v = Object.new\ndef v.deconstruct = nil\ncase v\nin *rest\nend\n",
  "find pattern" => "v = Object.new\ndef v.deconstruct = 1\ncase v\nin [*, 1, *]\nend\n",
  "keyword hash splat" => "v = Object.new\ndef v.to_hash = 1\n[**v]\n",
  "keyword hash key" => "k = Object.new\ndef k.hash = nil\n[k => 1]\n",
  "hash literal key" => "k = Object.new\ndef k.hash = :no\nx = {k => 1}\n",
  "array splat" => "v = Object.new\ndef v.to_a = 1\nr = *v\n",
  "singleton class" => "v = 1\nclass << v; rescue; end\n",
  "class" => "SourceRangeClassValue = 1\nclass SourceRangeClassValue; rescue; end\n",
  "module" => "SourceRangeModuleValue = 1\nmodule SourceRangeModuleValue; rescue; end\n",
  "lambda arity" => "-> { it }.call()\n",
  "stabby arity" => "value = ->(argument) {}\nvalue.call\n",
  "Kernel#lambda arity" => "value = lambda { |argument| }\nvalue.call\n",
  "lambda rescue arity" => "lambda do; rescue; end.call(1)\n",
  "numbered arity" => "value = lambda { _1 }\nvalue.call\n",
  "def arity" => "t = Class.new do\n  def m(first, second)\n    first + second\n  end\nend.new\nt.m(1)\n",
  "def rescue arity" => "v = Object.new\ndef v.f(a); rescue => e; e; end\nv.f()\n",
  "keyword arity" => "t = Object.new\ndef t . m(value:)\n  value\nend\nt.m\n",
  "define_method arity" => "t = Class.new do\n  define_method(:m) do |first, second|\n    first + second\n  end\nend.new\nt.m(1)\n"
}.freeze

CASES.each { |name, source| puts "#{name}: #{range_of(source)}" }

# Frame 1: the caller of a method whose arguments do not fit, and the
# statement that converted a value in a method it called.
FRAMES = {
  "caller of def arity" => "t = Class.new do\n  def m(first, second) = first\nend.new\nt.m(1)\n",
  "to_ary of a multiple assignment" => "v = Object.new\ndef v.to_ary = raise(TypeError)\nfirst, second = v\n",
  "to_a of a splatted value" => "v = Object.new\ndef v.to_a = raise(TypeError)\nfirst, second = *v\n",
  "to_ary of a nested target" => "v = Object.new\ndef v.to_ary = raise(TypeError)\n(first, second), third = v, 1\n",
  "to_ary of a block parameter" => "v = Object.new\ndef v.to_ary = raise(TypeError)\n[v].each { |(first, second)| }\n",
  "to_a of a when splat" => "v = Object.new\ndef v.to_a = raise(TypeError)\ncase nil\nwhen *v\nend\n",
  "to_a of a returned splat" => "v = Object.new\ndef v.to_a = raise(TypeError)\ndef t(v)\n  return *v\nend\nt(v)\n",
  "=== of a when value" => "o = Object.new\ndef o.===(x) = raise(TypeError)\ncase 1\nwhen o\nend\n",
  "=== of an in value" => "o = Object.new\ndef o.===(x) = raise(TypeError)\ncase 1\nin ^o\nend\n"
}.freeze

FRAMES.each { |name, source| puts "#{name}: #{range_of(source, 1)}" }

# The file must still have the code that ran: a deleted file raises the
# read's error, and a changed one raises RuntimeError. A data section
# after __END__ may change.
def location_of(source)
  File.binwrite(PATH, source)
  load PATH
rescue => e
  e.backtrace_locations.first
end

def try(label)
  r = yield.source_range
  puts "#{label}: #{[r.start_line, r.start_column, r.end_line, r.end_column]}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message.sub(DIR, "DIR")}"
end

l = location_of("nil.foo\n")
File.delete(PATH)
try("deleted") { l }
l = location_of("nil.foo\n")
File.binwrite(PATH, "(\n")
try("invalid now") { l }
l = location_of("first = 1\nsecond = 2\nnil.foo\n")
File.binwrite(PATH, "nil\n")
try("shorter now") { l }
l = location_of("nil.foo\n")
File.binwrite(PATH, "nil.longer_method_name\n")
try("same layout") { l }
l = location_of("nil.foo\n")
File.binwrite(PATH, "nil.foo\nnil.bar\n")
try("longer now") { l }
l = location_of("nil.foo\n__END__\ndata\n")
File.binwrite(PATH, "nil.foo\n__END__\nother data\n")
try("new data section") { l }
l = location_of("nil.foo\n")
File.binwrite(PATH, "nil.foo\n__END__\n")
try("added data section") { l }

# A TracePoint :call hook sees the frame at the body's first statement,
# while an arity error stands at the whole def.
r = nil
tp = TracePoint.new(:call) { r ||= caller_locations(1, 1)[0] }
File.binwrite(PATH, "def tp_method\n  x = 1\n  x + 1\nend\n")
load PATH
tp.enable { tp_method }
try("call hook") { r }
p RubyVM::AbstractSyntaxTree.node_id_for_backtrace_location(r).is_a?(Integer)
p r.syntax_tree.class
File.delete(PATH)
Dir.rmdir(DIR)
