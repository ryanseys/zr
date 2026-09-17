# frozen_string_literal: true

# The stage ladder. Stage 1 is the compiler compiled by ze0 under ruby;
# stage 2 is the same source compiled by stage 1. The two binaries must
# agree byte for byte, which is what says the compiler is a fixed point.
# Both are written under the same base name, since macOS's ad-hoc
# signature carries the output's base name.
#
# ze0's own linker links both, stage 2's inside the compiled compiler,
# so the comparison holds the linker to the same fixed point. Its UUID
# is the image's hash, and the signature hashes the image, so both
# follow from the rest. They are blanked all the same: under
# `ZE0_LINK=cc`, `ld` writes a fresh UUID each link and the signature
# over its page, and no input decides those.
#
#   rake stage2

require "fileutils"
require "rbconfig"
require_relative "../lib/ze0/cli"
require_relative "../lib/ze0/native/build"

Ze0::CLI.tune!(__FILE__)

ROOT = Ze0::Paths::ROOT
ZE0 = File.join(ROOT, "exe/ze0")
source = File.join(ROOT, "tools/stage.rb")

stages = (1..2).map do |n|
  dir = File.join(ROOT, "tmp/stage#{n}")
  FileUtils.rm_rf(dir)
  FileUtils.mkdir_p(File.join(dir, "cache"))
  File.join(dir, "ze0")
end
caches = stages.map { |path| { "ZE0_CACHE" => File.join(File.dirname(path), "cache") } }

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
Ze0::CLI.step("stage 1: ruby compiles the compiler -> #{stages[0]}") do
  system(caches[0], RbConfig.ruby, ZE0, "zr", "build", source, "-o", stages[0]) or
    abort("rake stage2: stage 1 did not build")
end
puts "stage 1: #{File.size(stages[0])} bytes"
Ze0::CLI.step("stage 2: stage 1 compiles the compiler -> #{stages[1]}") do
  system(caches[1], stages[0], source, "-o", stages[1]) or
    abort("rake stage2: stage 1 did not compile the compiler")
end

a, b = stages.map { |path| File.binread(path) }
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
linker = Ze0::Native::Build.linker(Ze0::Target.default)
stamps = linker.stamps(a)
x, y = [a, b].map do |bytes|
  bytes.dup.tap { |out| linker.stamps(bytes).each { |r| out[r] = "\0".b * r.size } }
end

if x == y
  puts format("stage 2 holds: %d bytes, the same from stage 1 and from ruby, in %.1f s", a.bytesize, elapsed)
  puts "the linker's own stamps are not compared: #{stamps.map { |r| "#{r.first}..#{r.last}" }.join(", ")}" unless stamps.empty?
  puts "both binaries are kept: #{stages.join(" and ")}"
else
  at = x.bytesize.times.find { |i| x.getbyte(i) != y.getbyte(i) } || [x.bytesize, y.bytesize].min
  abort("rake stage2: #{a.bytesize} and #{b.bytesize} bytes, first differing at #{at}")
end
