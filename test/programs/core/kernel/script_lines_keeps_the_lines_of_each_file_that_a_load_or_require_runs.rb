# SCRIPT_LINES__ keeps the lines of each file that a load or a require
# runs while the Hash is there, under the file's path, in the encoding of
# its magic comment (UTF-8 with none; after a shebang line, the comment
# on the second line).
require "tempfile"
Object.const_set(:SCRIPT_LINES__, {})
f = Tempfile.new(["lines", ".rb"])
%w[UTF-8 Shift_JIS EUC-JP Windows-1252 US-ASCII].each do |enc|
  f.open
  f.truncate(0)
  f.puts("# -*- coding: #{enc} -*-\n$x = 1")
  f.close
  load(f.path)
  lines = SCRIPT_LINES__[f.path]
  p [enc, SCRIPT_LINES__.keys == [f.path], lines.size, lines.map(&:encoding).uniq.map(&:name)]
end

f.open
f.truncate(0)
f.write("#!/usr/bin/env ruby\n# encoding: EUC-JP\n$y = 1")
f.close
load(f.path)
p [SCRIPT_LINES__[f.path].map(&:encoding).uniq, SCRIPT_LINES__[f.path]]

f.open
f.truncate(0)
f.write("$z = 2\n")
f.close
load(f.path)
p [SCRIPT_LINES__[f.path].map(&:encoding).uniq, SCRIPT_LINES__[f.path]]

# A require after the Hash is set gives it its file too.
require File.join(Dir.pwd, "lib", "sjis")
sjis = SCRIPT_LINES__.find { |k, _| k.end_with?("/lib/sjis.rb") }&.last
p [$required, SCRIPT_LINES__.size, sjis&.map(&:encoding)&.uniq, sjis]

# A value that is not a Hash keeps nothing, and nothing raises.
Object.send(:remove_const, :SCRIPT_LINES__)
Object.const_set(:SCRIPT_LINES__, [])
load(f.path)
p SCRIPT_LINES__
Object.send(:remove_const, :SCRIPT_LINES__)
load(f.path)
p defined?(SCRIPT_LINES__)
f.close!
