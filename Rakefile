# frozen_string_literal: true

# The standard entry points: build, test, lint, gen and release. Every
# other tool is a `zr-dev` command (`bin/zr-dev help`), and the tests run
# with `bin/minitest` (test/test_helper.rb lists its options).
require "bundler/setup"
require "rbconfig"

# Bundler's `build`, `install` and `release` tasks go under `gem:`.
# They refer to each other by bare names, so all of them go in this one
# namespace. Thus `rake build` stays free to build the runtime.
namespace :gem do
  require "bundler/gem_tasks"
end

# A release is a tag: the release workflow checks, builds and pushes the
# gem (docs/how-to/release.md). Bundler's own release task would push a
# gem that no CI run checked, so it stops too.
RELEASE = "Push a vX.Y.Z tag; see docs/how-to/release.md"
task(:release) { abort("rake release: #{RELEASE}") }
Rake::Task["gem:release"].clear
task("gem:release") { abort("rake gem:release: #{RELEASE}") }

ROOT = __dir__

# Runs `argv` with this ruby, and exits with its status when it fails.
def ruby!(*argv)
  system(RbConfig.ruby, *argv) || exit($?.exitstatus || 1)
end

# Builds the runtime for the targets that the Ruby expression names.
def build!(targets)
  ruby!("-I#{ROOT}/lib:#{ROOT}/test", "-e", %(require "support/built"; Zr::Test::Built.build(#{targets})))
end

desc "Build the zr runtime for this host (a test run also builds it when it is missing)"
task("build") { build!("Zr::Test::Built.targets") }

desc "Build the zr runtime for wasm32-wasi"
task("build:wasm") { build!("[Zr::Target::WASM32_WASI]") }

desc "Build the zr runtime for this host and for wasm32-wasi"
task("build:all") { build!("Zr::Test::Built.targets(wasm: true)") }

# The tiers, each one `bin/minitest` run. `bin/minitest <paths>` runs only
# some test files.
TIERS = {
  "test:unit" => ["test/unit", "zr's own internals"],
  "test:programs" => ["test/programs_test.rb", "Ruby programs that zr builds, each checked against ruby 4.0.7"]
}.freeze

TIERS.each do |name, (path, what)|
  desc what
  task(name) { ruby!(File.join(ROOT, "bin/minitest"), path) }
end

desc "Every test: unit, programs"
task test: TIERS.keys

desc "Write every generated file again (zr-dev gen all); CHECK=1 only compares"
task(:gen) { ruby!(File.join(ROOT, "tool/zr-dev.rb"), "gen", "all", *("--check" if ENV["CHECK"])) }

desc "Check the code with RuboCop's Lint cops (.rubocop.yml)"
task(:lint) { sh "rubocop", verbose: false }

desc "Lint, then every test"
task default: %i[lint test]
