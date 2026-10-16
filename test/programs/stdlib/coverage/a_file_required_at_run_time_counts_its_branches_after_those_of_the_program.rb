require "coverage"

# Files that the program writes and then requires: zr compiles each one
# while the program runs. Their branches count as a file's that the build
# compiled, and their counters come after the program's own.
Coverage.start(branches: true)
require_relative "built_in"
BUILT_IN = File.expand_path("built_in.rb", __dir__)

CODES = {
  "ifs" => <<~RUBY,
    def ifs(x)
      if x == 0
        0
      else
        1
      end

      unless x == 0
        0
      else
        1
      end

      x == 0 ? 0 : 1
      0 if x == 0
      1 unless x == 0
    end
    ifs(0); ifs(0); ifs(1)
  RUBY
  "loops" => <<~RUBY,
    def loops(n)
      i = 0
      while i < n
        i += 1
      end
      until i == 0
        i -= 1
      end
      i
    end
    loops(3)
  RUBY
  "cases" => <<~RUBY,
    def cases(x)
      case x
      when 1, 2 then :small
      when Integer then :int
      else :other
      end
    end
    def matches(x)
      case x
      in [a, b] then a + b
      in {k:} then k
      in Integer => n if n > 5 then n
      else :none
      end
    end
    [1, 3, "s", nil].each { cases(_1) }
    [[1, 2], {k: 3}, 9, 4].each { matches(_1) }
  RUBY
  "safe" => <<~RUBY,
    def safe(x) = x&.to_s&.size
    safe(nil); safe(12); safe(1)
  RUBY
  "ensures" => <<~RUBY,
    def ensures(x)
      yield
    ensure
      x ? :a : :b
    end
    ensures(true) {}
    ensures(false) {}
  RUBY
}.freeze

dir = Dir.pwd
CODES.each do |name, code|
  path = File.join(dir, "#{name}.rb")
  File.write(path, code)
  require path
end

result = Coverage.peek_result
CODES.each_key do |name|
  entry = result.fetch(File.join(dir, "#{name}.rb"))
  puts "#{name}: #{entry[:branches].inspect}"
end
puts "built in: #{result.fetch(BUILT_IN)[:branches].inspect}"

# The counters stay apart after more runs, and a clear empties them all.
ifs(1)
safe("x")
again = Coverage.result(stop: false, clear: true)
puts "ifs again: #{again.fetch(File.join(dir, "ifs.rb"))[:branches].values.map(&:values).inspect}"
puts "safe again: #{again.fetch(File.join(dir, "safe.rb"))[:branches].values.map(&:values).inspect}"
built_in(1)
after = Coverage.result
puts "after clear: #{after.fetch(File.join(dir, "ifs.rb"))[:branches].values.map(&:values).inspect}"
puts "built in after clear: #{after.fetch(BUILT_IN)[:branches].values.map(&:values).inspect}"
