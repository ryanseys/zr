# frozen_string_literal: true

# ze0 under ruby compiles the compiler twice, in two processes with a
# cache of its own each, and the bytes must agree: the self-compile
# stays deterministic and refusal-free with no binary in the loop. Both
# objects are compared, the compiler's and the runtime's. The stage-2
# fixed point needs a stage-1 binary that runs.
#
#   rake stage1

require "fileutils"
require "rbconfig"
require "tmpdir"
require_relative "../lib/ze0/cli"

Ze0::CLI.tune!(__FILE__)

ROOT = Ze0::Paths::ROOT
ZE0 = File.join(ROOT, "exe/ze0")
source = File.join(ROOT, "tools/stage.rb")

# The work directory outlives a failure, so the two objects and their
# caches are there to diff; a run that holds removes it, as the two
# objects are then the same bytes twice.
work = Dir.mktmpdir("ze0-stage1-")
puts "work (kept if this fails): #{work}"

outs = %w[a b].map do |n|
  cache = File.join(work, "#{n}-cache")
  FileUtils.mkdir_p(cache)
  out = File.join(work, "#{n}.o")
  Ze0::CLI.step("self-compile #{n} -> #{out}") do
    system({ "ZE0_CACHE" => cache, "RUBYOPT" => nil, "RUBYLIB" => nil },
           RbConfig.ruby, ZE0, "zr", "build", source, "-o", out, "--emit", "obj", chdir: ROOT) or
      abort("rake stage1: the self-compile failed; its work is in #{work}")
  end
  runtime = Dir[File.join(cache, "rt-*.o")]
  abort("rake stage1: the runtime object was not cached; the work is in #{work}") unless runtime.size == 1

  [File.binread(out), File.binread(runtime.first)]
end

a, b = outs
%w[compiler runtime].each_with_index do |what, i|
  next if a[i] == b[i]

  at = a[i].bytes.zip(b[i].bytes).index { |x, y| x != y } || [a[i].bytesize, b[i].bytesize].min
  abort("rake stage1: the two #{what} objects differ: #{a[i].bytesize} and #{b[i].bytesize} bytes, " \
        "first at #{at}; both are kept in #{work}")
end
puts "stage 1 holds: #{a[0].bytesize} bytes of compiler and #{a[1].bytesize} of runtime, the same twice"
FileUtils.rm_rf(work)
puts "nothing is kept: #{work} is gone"
