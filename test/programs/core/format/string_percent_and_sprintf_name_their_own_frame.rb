# The top frame of an error that a format spec or its arguments raise
# names the method that the program called: Kernel#format,
# Kernel#sprintf or String#%. Found by zr-dev fuzz.
def top(label)
  value = yield
  puts "#{label}: #{value.inspect}"
rescue StandardError => e
  frame = e.backtrace_locations.first
  puts "#{label}: #{e.class}: #{e.message} (#{frame.label}, line #{frame.lineno})"
end

top("format bad spec") { format("%z") }
top("sprintf bad spec") { sprintf("%z") }
top("% bad spec") { "%z" % 1 }
top("% bad spec, array") { "%z" % [1] }
top("% too few") { "%d %d" % [1] }
top("format too few") { format("%d %d", 1) }
top("sprintf too few") { sprintf("%d %d", 1) }
top("% bad Integer") { "%d" % "x" }
top("format bad Integer") { format("%d", "x") }
top("% bad Float") { "%f" % "x" }
top("sprintf no conversion") { sprintf("%d", Object.new) }
top("% missing key") { "%<a>s" % { b: 1 } }
top("format missing key") { format("%{a}", {}) }
top("format no arguments") { format }
top("sprintf no arguments") { sprintf }
top("Kernel.format") { Kernel.format("%z") }
top("Kernel.sprintf") { Kernel.sprintf("%z") }
top("send(:format)") { send(:format, "%z") }
top("method(:sprintf).call") { method(:sprintf).call("%z") }

# The working forms are the same.
top("format") { format("%05.1f|%-4s|%x", 3.14159, "ab", 255) }
top("sprintf") { sprintf("%+d %o", 5, 8) }
top("%") { "%s and %p" % ["a", :b] }
top("% hash") { "%<n>03d" % { n: 7 } }
top("% one") { "%.2e" % 12345.678 }

# Reflection: each method has its own name, and no helper shows.
p method(:format).name, method(:sprintf).name
p method(:format).original_name, method(:sprintf).original_name
p Kernel.private_method_defined?(:format), Kernel.private_method_defined?(:sprintf)
p Kernel.respond_to?(:formatted, true), Kernel.singleton_methods.include?(:formatted)
p "".method(:%).owner, "".method(:%).arity

# A rescue in a method names the method's own frame below the format frame.
def render(spec, *args) = spec % args

begin
  render("%z", 1)
rescue ArgumentError => e
  p e.backtrace_locations.first(2).map(&:label)
end
