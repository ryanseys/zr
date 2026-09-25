# frozen_string_literal: true

# The standard entry points: build, test, lint, gen and release. Every
# other tool is a `zr-dev` command (`ruby tool/zr-dev.rb help`), and the
# tests take paths and options through bin/test.
require "bundler/setup"
require "rbconfig"

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

# Every task runs the compiler under ruby. `ZR_COMPILED=1` selects the
# compiled compiler (lib/zr/compiled_compiler.rb).
ENV["ZR_COMPILED"] ||= "0"

# Runs `argv` with this ruby, and exits with its status when it fails.
def ruby!(*argv)
  system(RbConfig.ruby, *argv) || exit($?.exitstatus || 1)
end

# Builds the runtime for the targets that the Ruby expression names.
def build!(targets)
  ruby!("-I#{ROOT}/lib:#{ROOT}/test", "-e", %(require "support/built"; Zr::Test::Built.build(#{targets})))
end

desc "Build the zr runtime for this host (bin/test also builds it when it is missing)"
task("build") { build!("Zr::Test::Built.targets") }

desc "Build the zr runtime for wasm32-wasi"
task("build:wasm") { build!("[Zr::Target::WASM32_WASI]") }

desc "Build the zr runtime for this host and for wasm32-wasi"
task("build:all") { build!("Zr::Test::Built.targets(wasm: true)") }

desc "Build the compiler with itself (exe/zr uses it until a file under lib, runtime or vendor changes)"
task("build:self") do
  require_relative "lib/zr/compiled_compiler"
  Zr::CompiledCompiler.build
  abort("rake build:self: the compiled compiler did not build") unless Zr::CompiledCompiler.current?
  puts "the compiled compiler: #{Zr::CompiledCompiler.binary}"
end

# The tiers. bin/test tunes the collector, builds the runtime when it is
# missing, and reads TARGET=, GC=stress, SLOW=, N=, X=, A= and MT_CPU=.
# `bin/test <paths>` runs only some test files.
TIERS = {
  "test:unit" => ["test/unit", "zr's own internals"],
  "test:spec" => ["test/spec", "Ruby specs, each checked against ruby 4.0.6"],
  "test:e2e" => ["test/e2e", "Whole programs, built and linked, checked against ruby 4.0.6"]
}.freeze

TIERS.each do |name, (dir, what)|
  desc what
  task(name) { ruby!(File.join(ROOT, "bin/test"), dir) }
end

desc "Every test: unit, spec, e2e"
task test: TIERS.keys

desc "Write every generated file again (zr-dev gen all); CHECK=1 only compares"
task(:gen) { ruby!(File.join(ROOT, "tool/zr-dev.rb"), "gen", "all", *("--check" if ENV["CHECK"])) }

desc "Check the code with RuboCop's Lint cops (.rubocop.yml)"
task(:lint) { sh "rubocop", verbose: false }

desc "Lint, then every test"
task default: %i[lint test]
