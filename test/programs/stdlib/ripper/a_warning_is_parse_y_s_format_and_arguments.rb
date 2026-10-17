# Ripper calls `warn` or `warning` with parse.y's format and its
# arguments, not the message they make. The useless use of a value and a
# mismatched indentation warn only when $VERBOSE is true, the others at
# any $VERBOSE, and an unused local is no warning; an operator that seems
# to start an argument is its own event.
require "ripper"

class Warnings < Ripper
  def warn(format, *args) = (@log ||= []) << [:warn, format, *args]
  def warning(format, *args) = (@log ||= []) << [:warning, format, *args]
  def on_operator_ambiguous(operator, syntax) = (@log ||= []) << [:operator_ambiguous, operator, syntax]

  def self.of(source) = new(source).tap(&:parse).instance_variable_get(:@log)
end

sources = [
  "a = 1; a -1", "a = 1; a %[]", "a = 1; a *[1]", "a = 1; a **h", "a = 1; a &b", "a < b < c",
  "if a = 1\nend", "def m; END { }; end", "{ a: 1, a: 2 }", "{ 'k' => 1, 'k' => 2 }", "{ 1 => 1, 1 => 2 }",
  "case 1\nwhen 1\nwhen 1\nend", "1e999", "1; # frozen_string_literal: true", "# frozen_string_literal: nottrue",
  "if true\n  end", "if 1..2\nend", "p $10000000000", "if 1\nend", "def m; return; 1; end", "1", "\r;",
  "foo *a", "foo &a", "foo **a", "x = 1"
]
[nil, false, true].each do |verbose|
  puts "$VERBOSE = #{verbose.inspect}"
  sources.each do |source|
    $VERBOSE = verbose
    log = Warnings.of(source)
    $VERBOSE = false
    p [source, log]
  end
end
