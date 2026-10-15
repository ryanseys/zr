# A require of a name with a byte that is no character searches the load
# path as any other name does, and raises LoadError. With rubygems loaded,
# bundled_gems' LoadError#message reads the path with String#tr, which
# raises for that byte, so the uncaught error shows only its class.
Gem
["\xff", "a\xfe/b", "\xff.rb", "\xff.so", "./\xff"].each do |name|
  %i[require load].each do |kind|
    send(kind, name)
  rescue LoadError => e
    puts "#{kind} #{name.inspect}: #{e.class}, path #{e.path.inspect}"
    puts "  message: #{(e.message rescue $!).inspect}"
  end
end
begin
  require_relative "\xff"
rescue LoadError => e
  puts "require_relative: #{e.class}"
end
require(("\xff"))
