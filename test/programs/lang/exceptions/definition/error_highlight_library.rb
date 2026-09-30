# error_highlight is loaded before the program, as ruby's gem prelude
# loads it: a require of it answers false, and `detailed_message` shows
# the line with a caret run under the call that failed. The program
# carries no parser; the compiler found each spot while it held the tree.

p require("error_highlight")
p defined?(ErrorHighlight)
p ErrorHighlight.respond_to?(:spot)

def boom
  nil.nope
rescue NoMethodError => e
  puts e.detailed_message(highlight: false)
end
boom

