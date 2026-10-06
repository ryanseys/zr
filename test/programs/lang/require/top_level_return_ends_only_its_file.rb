# ruby's top-level `return` ends the FILE it is written in; reading
# resumes in the file that required it.
#
# Each file that writes one gets its own end to jump to, and every later
# run of that file -- and every run spliced inside it -- is skipped.
#
# `vendor/ext/digest/lib/digest.rb:12` opens with a guarded one, and
# stdlib files use the form to bail out early.

puts "main: start"
require_relative "top_level_return/stops"
puts "main: after stops"
p defined?(STOPS_MARK)
p defined?(NEVER_REQUIRED)

require_relative "top_level_return/runs"
puts "main: after runs"

# It carries through a `require_relative` the returning file writes itself,
# and out of a `begin`/`rescue` around it.
require_relative "top_level_return/nested"
puts "main: after nested"
require_relative "top_level_return/guarded"
puts "main: after guarded"
