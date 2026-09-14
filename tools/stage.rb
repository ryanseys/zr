# frozen_string_literal: true

# The compiler as a program ze0 can compile: `stage <file.rb> -o <out>`
# builds a native binary the way `ze0 zr build` does, with no ruby in the
# loop. Compiled by ze0 under ruby it is stage 1; run to compile itself
# again it is stage 2, and the two binaries must agree byte for byte.

require "tmpdir"
require_relative "../lib/ze0/zr"
require_relative "../lib/ze0/native/build"

def usage
  warn("stage <file.rb> -o <out>")
  exit(1)
end

file = nil
out = nil
argv = ARGV.dup
until argv.empty?
  case (arg = argv.shift)
  when "-o" then out = argv.shift
  else file = arg
  end
end
usage unless file && out

program = Ze0::Zr.program(File.read(file), File.expand_path(file))
why = Dir.mktmpdir("ze0-stage-") do |work|
  Ze0::Native::Build.program(program, out, work: work)
end
abort("stage: #{why}") if why
puts "#{out}: #{File.size(out)} bytes"
