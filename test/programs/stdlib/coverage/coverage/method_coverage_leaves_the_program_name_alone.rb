# Method coverage keeps its rows apart from the program's name, so
# Process.argv0 is still the String that $0 started as.
require "coverage"
Coverage.start(methods: true)
require_relative "argv0/measured"

measured_twice(1)
p Process.argv0.class
p File.basename(Process.argv0)
p Coverage.result.find { |path, _| File.basename(path) == "measured.rb" }.last[:methods].values
