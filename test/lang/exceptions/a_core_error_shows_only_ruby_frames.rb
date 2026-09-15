# An error a core method raises shows the frames of the methods the
# program called and the C methods ruby shows, and none of the helpers
# the runtime keeps for itself: in a block, in sort_by, in Integer(), in
# JSON.parse, in fetch, in eval and in Comparable.
require "json"
def show
  yield
rescue Exception => e
  puts "#{e.class}: #{e.message}"
  puts e.backtrace_locations.map { |l| "#{File.basename(l.path)}:#{l.lineno}:#{l.label}" }
end
show { "a\xffb".force_encoding("UTF-8").grapheme_clusters.map { |c| c.foo } }
show { [3, 1].sort_by { |x| x.zork } }
show { %w[1 x].map { |v| Integer(v) } }
show { JSON.parse("{") }
show { {a: 1}.fetch(:b) }
show { [1].fetch(5) }
show { [1, "a"].sort }
show { [1, 2].each_slice(0) }
show { "abc".unpack("@9") }
show { [1, 2].min_by { |x| raise "in min_by" } }
show { {a: 1}.each { |k, v| raise "in each" } }
show { eval("1 +") }
show { Struct.new(:a).new(1, 2) }
show { "x".encode("NOPE") }
show { Comparable.instance_method(:clamp).bind_call(3, 5, 1) }

__END__
NoMethodError: undefined method 'foo' for an instance of String
a_core_error_shows_only_ruby_frames.rb:12:block (2 levels) in <main>
a_core_error_shows_only_ruby_frames.rb:12:Array#map
a_core_error_shows_only_ruby_frames.rb:12:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:12:<main>
NoMethodError: undefined method 'zork' for an instance of Integer
a_core_error_shows_only_ruby_frames.rb:13:block (2 levels) in <main>
a_core_error_shows_only_ruby_frames.rb:13:Array#each
a_core_error_shows_only_ruby_frames.rb:13:Enumerable#sort_by
a_core_error_shows_only_ruby_frames.rb:13:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:13:<main>
ArgumentError: invalid value for Integer(): "x"
a_core_error_shows_only_ruby_frames.rb:14:Kernel#Integer
a_core_error_shows_only_ruby_frames.rb:14:block (2 levels) in <main>
a_core_error_shows_only_ruby_frames.rb:14:Array#map
a_core_error_shows_only_ruby_frames.rb:14:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:14:<main>
JSON::ParserError: expected object key, got EOF at line 1 column 2
common.rb:364:JSON::Ext::Parser.parse
common.rb:364:JSON.parse
a_core_error_shows_only_ruby_frames.rb:15:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:15:<main>
KeyError: key not found: :b
a_core_error_shows_only_ruby_frames.rb:16:Hash#fetch
a_core_error_shows_only_ruby_frames.rb:16:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:16:<main>
IndexError: index 5 outside of array bounds: -1...1
a_core_error_shows_only_ruby_frames.rb:17:Array#fetch
a_core_error_shows_only_ruby_frames.rb:17:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:17:<main>
ArgumentError: comparison of Integer with String failed
a_core_error_shows_only_ruby_frames.rb:18:Array#sort
a_core_error_shows_only_ruby_frames.rb:18:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:18:<main>
ArgumentError: invalid slice size
a_core_error_shows_only_ruby_frames.rb:19:Enumerable#each_slice
a_core_error_shows_only_ruby_frames.rb:19:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:19:<main>
ArgumentError: @ outside of string
a_core_error_shows_only_ruby_frames.rb:20:String#unpack
a_core_error_shows_only_ruby_frames.rb:20:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:20:<main>
RuntimeError: in min_by
a_core_error_shows_only_ruby_frames.rb:21:block (2 levels) in <main>
a_core_error_shows_only_ruby_frames.rb:21:Array#each
a_core_error_shows_only_ruby_frames.rb:21:Enumerable#min_by
a_core_error_shows_only_ruby_frames.rb:21:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:21:<main>
RuntimeError: in each
a_core_error_shows_only_ruby_frames.rb:22:block (2 levels) in <main>
a_core_error_shows_only_ruby_frames.rb:22:Hash#each
a_core_error_shows_only_ruby_frames.rb:22:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:22:<main>
SyntaxError: (eval at lang/exceptions/a_core_error_shows_only_ruby_frames.rb:23):1: syntax errors found
> 1 | 1 +
    |    ^ unexpected end-of-input, assuming it is closing the parent top level context
    |    ^ unexpected end-of-input; expected an expression after the operator
a_core_error_shows_only_ruby_frames.rb:23:Kernel#eval
a_core_error_shows_only_ruby_frames.rb:23:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:23:<main>
ArgumentError: struct size differs
a_core_error_shows_only_ruby_frames.rb:24:Struct#initialize
a_core_error_shows_only_ruby_frames.rb:24:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:24:<main>
Encoding::ConverterNotFoundError: code converter not found (UTF-8 to NOPE)
a_core_error_shows_only_ruby_frames.rb:25:String#encode
a_core_error_shows_only_ruby_frames.rb:25:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:25:<main>
ArgumentError: min argument must be less than or equal to max argument
a_core_error_shows_only_ruby_frames.rb:26:Comparable#clamp
a_core_error_shows_only_ruby_frames.rb:26:UnboundMethod#bind_call
a_core_error_shows_only_ruby_frames.rb:26:block in <main>
a_core_error_shows_only_ruby_frames.rb:7:Object#show
a_core_error_shows_only_ruby_frames.rb:26:<main>
