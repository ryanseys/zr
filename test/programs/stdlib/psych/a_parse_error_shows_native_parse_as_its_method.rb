# Psych's parser walks the events in C (_native_parse), so a parse error
# or a handler's error shows _native_parse as the method below it, with
# no frame of the walk.
require "psych"
def labels(e) = e.backtrace_locations.map(&:label)
begin; Psych.parse("\xff"); rescue Psych::SyntaxError => e; p labels(e); end
begin; Psych.parse("a: [1"); rescue Psych::SyntaxError => e; p labels(e), e.message; end
class H < Psych::Handler; def scalar(*) = raise("boom"); end
begin; Psych::Parser.new(H.new).parse("a"); rescue => e; p labels(e); end
p Psych.load("a: [1, 2]")
