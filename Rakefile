# frozen_string_literal: true

require "bundler/setup"

# bundler's own `build`, `install` and `release`, under `gem:`. They
# name each other by the bare names inside this block, so the namespace
# holds for the whole family, and `rake build` is left to mean what
# anyone working here builds: the runtime.
namespace :gem do
  require "bundler/gem_tasks"
end

# rubygems/release-gem runs `rake release`.
desc "Build the gem, tag it and push it to rubygems.org"
task release: "gem:release"

ROOT = __dir__

# The task bodies live in `rakelib/*.rake`, which rake loads after this
# file, so what is here is what they share: the checkout's root, the
# load path the compiler and the test support want, and the collector
# tuning a compile wants.
$LOAD_PATH.unshift(File.join(ROOT, "lib"), File.join(ROOT, "test"))

# The collector limits and YJIT of a compile (`Zr::CLI.tune!`). A rake
# task cannot start itself again, so the limits go to its child processes.
def zr_tune!
  require "zr/cli"
  Zr::CLI.tune!
end

# A generated file, written whole: the task prints into a string and the
# file is replaced only once all of it is there, so a generator that
# stops half way leaves the old file standing.
def zr_write(path)
  require "stringio"
  io = StringIO.new
  yield io
  File.write(File.join(ROOT, path), io.string)
  puts "wrote #{path} (#{io.string.lines.size} lines)"
end

# `TARGET=<triple>` builds and runs every program for that target, and
# `GC=stress` collects at every allocation. bin/test reads the same two.
ENV["ZR_TARGET"] = ENV["TARGET"] if ENV["TARGET"]
ENV["ZR_GC_STRESS"] = "1" if ENV["GC"] == "stress"
# Every task runs the compiler under ruby, unless `ZR_SELF=1` asks for
# the compiled compiler (lib/zr/self_host.rb).
ENV["ZR_SELF"] ||= "0"

desc "Build the zr runtime for this host (bin/test also builds it when it is missing)"
task("build") { zr_build("Zr::Test::Built.targets") }

desc "Build the zr runtime for wasm32-wasi"
task("build:wasm") { zr_build("[Zr::Target::WASM32_WASI]") }

desc "Build the zr runtime for this host and for wasm32-wasi"
task("build:all") { zr_build("Zr::Test::Built.targets(wasm: true)") }

desc "Build the compiler with itself (exe/zr uses it until a file under lib, rt or vendor changes)"
task("build:self") do
  require_relative "lib/zr/self_host"
  Zr::SelfHost.build
  abort("rake build:self: the compiled compiler did not build") unless Zr::SelfHost.current?
  puts "the compiled compiler: #{Zr::SelfHost.binary}"
end

def zr_build(targets)
  require "rbconfig"
  sh(RbConfig.ruby, "-Ilib:test", "-e", %(require "support/built"; Zr::Test::Built.build(#{targets})), verbose: false)
end

# Runs bin/test with `args`, and exits with its status when it fails.
# bin/test tunes the collector, builds the runtime when it is missing,
# and reads N=, X=, A=, SLOW and MT_CPU.
def zr_bin_test(*args)
  require "rbconfig"
  system(RbConfig.ruby, File.join(ROOT, "bin/test"), *args) || exit($?.exitstatus || 1)
end

TIERS = {
  "test:unit" => ["test/unit", "zr's own internals"],
  "test:spec" => ["test/spec", "Ruby specs, each checked against ruby 4.0.6"],
  "test:e2e" => ["test/e2e", "Whole programs, built and linked, checked against ruby 4.0.6"]
}.freeze

TIERS.each do |name, (dir, what)|
  desc what
  task(name) { zr_bin_test(dir) }

  desc "#{what}, and the 25 slowest files"
  task("#{name}:slow") do
    ENV["SLOW"] = "1"
    zr_bin_test(dir)
  end
end

# `rake test test/unit/prism_test.rb`, a bare `prism_test.rb`, or a
# directory. Rake reads each word as a task name, so a word that names a
# test becomes an empty task here, and `test` gives the words to bin/test.
ZR_TEST_ARGV = ARGV.drop(1).select do |word|
  next false if word.include?("=") || word.start_with?("-")

  path = File.expand_path(word, ROOT)
  test = (File.exist?(path) && path.start_with?(File.join(ROOT, "test"))) ||
         word.start_with?("test/") || word.end_with?("_test.rb") || Dir[File.join(ROOT, "test/**", word)].any?
  task(word) {} if test
  test
end

desc "Where the tier running now stands, or the last one stood (tmp/test-progress.txt)"
task("test:progress") do
  require_relative "test/support/progress"
  puts(Zr::Test::Progress.read || "no tier has run yet")
end

desc "Every test (unit, spec, e2e), or only the test files that follow"
if ZR_TEST_ARGV.empty?
  task test: TIERS.keys
else
  task(:test) { zr_bin_test(*ZR_TEST_ARGV) }
end

task default: :test
