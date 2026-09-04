#!/usr/bin/env ruby
# frozen_string_literal: true

# ze0: a Ruby front end for zeo's backend, written in Ruby.
#
#   ze0 <file.rb> -o <out.clif>      writes out.clif and out.zeodata
#   zeo backend out.clif -o <bin>    links them
#
# It lowers a subset of Ruby -- literals and string interpolation, Array,
# Hash and Range literals, locals, globals, instance variables and
# constants, Integer arithmetic and comparison, if/unless/while/until,
# case/when, classes and modules, defs and blocks with the whole parameter
# surface, return, closures with next/break/yield, puts, and any
# other call as a dynamic send -- to the CLIF text zeo's Rust emitter would
# write in its outlined form. A form outside the subset is refused by name;
# nothing is compiled to something that answers differently from ruby.

require_relative "lib/ze0"

def usage
  warn "usage: ze0 [-I <dir>] <file.rb> -o <out.clif>"
  exit 2
end

input = nil
output = nil
roots = []
args = ARGV.dup
until args.empty?
  arg = args.shift
  case arg
  when "-o" then output = args.shift or usage
  # A root a plain `require` searches, in the order given. A feature no
  # root carries is one the runtime already holds.
  when "-I" then roots << (args.shift or usage)
  when /\A-/ then usage
  else
    usage if input
    input = arg
  end
end
usage unless input && output

begin
  source = File.read(input)
rescue SystemCallError => e
  warn "ze0: #{e.message}"
  exit 1
end

# The Ruby halves of the extensions the runtime carries, searched after
# the roots `-I` named. `zeo build` splices the same files, so a plain
# `require "json"` reaches one library on both roads. An installed ze0
# outside the tree finds none, and the require stays the runtime's.
def default_roots
  Dir[File.expand_path("../crates/zeo-rt/ext/*/lib", __dir__)].sort
end

begin
  clif, zeodata = Ze0.compile(source, input, roots + default_roots)
rescue Ze0::Unsupported => e
  warn "ze0: #{e.file || input}: #{e.message}"
  exit 1
rescue SyntaxError => e
  warn "ze0: #{e.message}"
  exit 1
end
File.write(output, clif)
File.write(output.sub(/\.clif\z/, "") + ".zeodata", zeodata)
