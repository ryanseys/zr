# A jump with nowhere to go is a parse error, so sexp is nil, and the
# state after a heredoc's end is the state its body had.
require "ripper"
class Errors < Ripper::SexpBuilder
  def on_parse_error(message) = (print "#{message}; "; super)
end
["yield 1", "break", "next", "redo", "-> { yield }", "module M; yield; end", "def f = yield", "[].each { break }"].each do |source|
  Errors.new(source).parse
  puts Ripper.sexp(source).nil?
end
p Ripper.lex("<<~X\n  q\nX\nx").map { |(_, event, _, state)| [event, state.to_s] }
