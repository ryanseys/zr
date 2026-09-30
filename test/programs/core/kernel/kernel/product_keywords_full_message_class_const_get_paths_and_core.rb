def t
  p yield
rescue StandardError => e
  puts "#{e.class}: #{e.message}"
end
t { Enumerator.product([1, 2], [3], k: 1) }
t { Enumerator.product([1, 2], [3], k: 1, j: 2) }
t { e = RuntimeError.new("m"); def e.detailed_message(**) = nil; e.full_message(highlight: false).sub(/\A.*?: /, "") }
t { RuntimeError.new("").full_message(highlight: false).sub(/\A.*?: /, "") }
t { Object.const_get("Nope::") }
t { Object.const_get("String::Nope::") }
t { Object.const_get("Nope::String") }
t { Kernel.method(:loop).source_location }
t { 1.method(:times).inspect }
t { Kernel.method(:Integer).inspect }
