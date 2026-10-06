# A file that leaves $LOADED_FEATURES and is required again runs again
# each time, also from many threads at once.
$runs = 0
path = File.expand_path("again/counted.rb", __dir__)
3.times do
  p require(path)
  p require(path)
  $LOADED_FEATURES.delete(path)
end
p $runs

threads = Array.new(8) do
  Thread.new do
    50.times do
      require path
      $LOADED_FEATURES.delete_if { |feature| Regexp.new(Regexp.escape(path)) =~ feature }
    end
  end
end
threads.each(&:join)
p $runs.between?(4, 3 + (8 * 50))
p $LOADED_FEATURES.include?(path)

# The same pattern built again is a new Regexp each time, and its
# warnings print each time.
$VERBOSE = true
a = Regexp.new("[aa]")
b = Regexp.new("[aa]")
p [a == b, a.equal?(b), a.frozen?, a.source.frozen?, a.source.equal?(a.source)]
a.source << "x"
p a.source
p a.match?("a")
