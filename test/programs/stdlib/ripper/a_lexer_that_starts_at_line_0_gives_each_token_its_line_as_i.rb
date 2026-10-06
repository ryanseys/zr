# irb puts a line that declares its local variables before the code
# and lexes from line 0, so the code starts at line 1.
require "ripper"
p Ripper::Lexer.new("x=nil;\np x\n", "-", 0).scan.map { |t| [t.pos, t.event, t.tok] }
