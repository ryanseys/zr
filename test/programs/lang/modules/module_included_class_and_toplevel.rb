# A module included BOTH into a class and at toplevel. A method of the module
# that constructs an object answers that object in both places.
#
# The shape comes from tobi/try (a Ruby CLI + TUI): its TUI helper module is
# mixed into the screen classes and also included at toplevel, so the script
# body can call the same helpers.
class Box
  attr_reader :ch
  def initialize(ch); @ch = ch; end
end

module Helpers
  def fill(ch); Box.new(ch); end
end

class Screen
  include Helpers          # included into a class...
  def go; fill("="); end
end

include Helpers            # ...AND at toplevel

puts Screen.new.go.ch
puts fill("-").ch

# a second method on the same module, to show it is not specific to one name
module More
  def wrap(ch); Box.new("[#{ch}]"); end
end

class Panel
  include More
  def draw; wrap("x"); end
end

include More

puts Panel.new.draw.ch
puts wrap("y").ch
