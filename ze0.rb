#!/usr/bin/env ruby
# frozen_string_literal: true

# ze0: a Ruby compiler, written in Ruby.
#
#   ze0 <file.rb> -o <out.clif>      writes out.clif and out.zeodata
#
# It lowers Ruby -- literals and string interpolation, Array, Hash and
# Range literals, locals, globals, instance variables and constants,
# Integer arithmetic and comparison, if/unless/while/until, case/when,
# classes and modules, defs and blocks with the whole parameter surface,
# return, closures with next/break/yield, and any other call as a dynamic
# send -- to Cranelift IR text in outlined form, one function per Ruby
# body, calling the runtime by name. A form outside the subset is refused
# by name; nothing is compiled to something that answers differently from
# ruby.

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

# Where a library ze0 splices comes from, highest precedence first: the
# Ruby halves of the extensions the runtime carries (`vendor/ext`), then
# rubygems and bundler (`vendor/ruby`), then the store zeo's `Gemfile.lock`
# resolves (`vendor/gems/gems`, directories named `<name>-<version>`). The
# last two are fetched, not committed; a tier that is absent is skipped.
TIERS = %w[vendor/ext vendor/ruby vendor/gems/gems].freeze

# The two libraries the store unpacks that no `require` may reach. `rbs`
# opens by loading a C extension nothing here builds, and `rubygems-update`
# names a require path of its own that is not `lib`.
WITHHELD = %w[rbs rubygems-update].freeze

# The libraries the runtime ships, searched after the roots `-I` named and
# in the order `zeo build` searches them: one library per name, the highest
# tier that carries it. Both roads splice the same files, so a plain
# `require "csv"` reaches one library on either. An installed ze0 outside
# the tree finds none, and the require stays the runtime's.
def default_roots
  root = __dir__
  TIERS.flat_map { |tier| Dir[File.join(root, tier, "*/lib")].sort }
       .reject { |dir| WITHHELD.include?(library_name(dir)) }
       .uniq { |dir| library_name(dir) }
end

# The name a tier directory serves, with the store's version suffix off.
def library_name(dir)
  File.basename(File.dirname(dir)).sub(/-\d[^-]*\z/, "")
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
