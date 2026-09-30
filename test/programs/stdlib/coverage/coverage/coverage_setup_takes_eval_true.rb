require "coverage"
Coverage.setup(lines: true, eval: true)
p Coverage.running?
Coverage.resume
p Coverage.running?
p Coverage.result.class
