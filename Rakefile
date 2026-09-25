# frozen_string_literal: true

require "bundler/setup"

# Bundler's `build`, `install` and `release` tasks go under `gem:`.
# They refer to each other by bare names, so all of them go in this one
# namespace. Thus `rake build` stays free to build the runtime.
namespace :gem do
  require "bundler/gem_tasks"
end

# rubygems/release-gem runs `rake release`.
desc "Build the gem, tag it and push it to rubygems.org"
task release: "gem:release"

ROOT = __dir__

# Rake loads the task bodies from `rakelib/*.rake` after this file.
# This file contains only what they share: the root, the load path for
# the compiler and the test support, and the collector tuning.
$LOAD_PATH.unshift(File.join(ROOT, "lib"), File.join(ROOT, "test"))

# Sets the collector limits and YJIT for a compile (`Zr::CLI.tune!`).
# A rake task cannot restart itself, so the limits apply only to its
# child processes.
def zr_tune!
  require "zr/cli"
  Zr::CLI.tune!
end

# `TARGET=<triple>` builds and runs every program for that target, and
# `GC=stress` collects at every allocation. bin/test reads the same two.
ENV["ZR_TARGET"] = ENV["TARGET"] if ENV["TARGET"]
ENV["ZR_GC_STRESS"] = "1" if ENV["GC"] == "stress"
# Every task runs the compiler under ruby. `ZR_COMPILED=1` selects the
# compiled compiler (lib/zr/compiled_compiler.rb).
ENV["ZR_COMPILED"] ||= "0"

desc "Build the zr runtime for this host (bin/test also builds it when it is missing)"
task("build") { zr_build("Zr::Test::Built.targets") }

desc "Build the zr runtime for wasm32-wasi"
task("build:wasm") { zr_build("[Zr::Target::WASM32_WASI]") }

desc "Build the zr runtime for this host and for wasm32-wasi"
task("build:all") { zr_build("Zr::Test::Built.targets(wasm: true)") }

desc "Build the compiler with itself (exe/zr uses it until a file under lib, runtime or vendor changes)"
task("build:self") do
  require_relative "lib/zr/compiled_compiler"
  Zr::CompiledCompiler.build
  abort("rake build:self: the compiled compiler did not build") unless Zr::CompiledCompiler.current?
  puts "the compiled compiler: #{Zr::CompiledCompiler.binary}"
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

# Accepts `rake test test/unit/prism_test.rb`, a bare `prism_test.rb`,
# or a directory. Rake reads each word as a task name. Thus each word
# that refers to a test becomes an empty task here, and `test` gives the
# words to bin/test.
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

desc "Write every generated file again (tool/gen); CHECK=1 only compares"
task(:gen) { sh(RbConfig.ruby, File.join(ROOT, "tool/zr-dev.rb"), "gen", "all", *("--check" if ENV["CHECK"]), verbose: false) }

desc "Check the code with RuboCop's Lint cops (.rubocop.yml)"
task(:lint) { sh "rubocop", verbose: false }

task default: %i[lint test]
