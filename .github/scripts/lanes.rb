# frozen_string_literal: true

# The lanes of CI (.github/workflows/lane.yml): one for each target in
# Zr::Target::ALL, on a runner of its host. A lane builds or restores its
# runtime, then runs the unit files and the programs of its target. The
# nightly run and a run by hand also run all of its programs, in shards.
# A target that Target::SUPPORT calls experimental does not fail the run.
#
#   ruby .github/scripts/lanes.rb matrix          the lanes, as JSON
#   ruby .github/scripts/lanes.rb units TRIPLE    the unit files of a lane
#   ruby .github/scripts/lanes.rb untagged        the unit files of no lane
#
# With --run, `units` and `untagged` run bin/minitest on the files.
#
# A unit file goes to the lanes of the kinds of host that it names
# (`# zr-test: on KIND...`, Zr::Test::Needs::KINDS). A file that builds
# programs (`# zr-test: runtime` or `eval`) and names no kind goes to
# each lane that runs on its target's own host, outside a container: it
# tests the runtime of that target. Any other file is untagged: one job
# on Linux runs it (ci.yml, `units`).

require "json"
require_relative "../../lib/zr/target"
require_relative "../../test/support/needs"

module Lanes
  ROOT = File.expand_path("../..", __dir__)

  # The runner of each target, and what its lane differs in:
  # - jobs: ZR_JOBS for the runtime build, which sets the workers and
  #   turns off the memory bound. No lane sets it: a build takes the
  #   cores up to 6, and Parallel.afforded keeps the workers inside the
  #   free memory (a macos-26 runner has 7 GB, an x86_64 Linux one 16 GB),
  #   and ZR_TIMING prints the count that it chose.
  # - verify: "0" builds the runtime with no IR check, which the aarch64
  #   Linux lane makes on the same passes; the bundle is the same.
  # - container: the lane runs in the pinned ruby's Alpine image.
  # - host: the runtime that the lane's tests also build for, as the test
  #   harness builds its host's (test/support/built.rb, `targets`).
  # - shards: the number of nightly program shards, for about 45 minutes
  #   each.
  # - seconds: ZR_TEST_SECONDS, the bound of one program's build and run,
  #   for a runner or a container that builds slowly.
  # - build_timeout: the minutes of the runtime build step, under the
  #   job's timeout, so a build that runs long fails, and the next steps
  #   keep its cache and its log. A runner that is lost keeps neither:
  #   darwin's runner was lost after 67 to 74 minutes of a build, where a
  #   cold build takes 10 to 20.
  # - tier: what the lane's failure stops (docs/how-to/release.md). A
  #   release takes each lane whose tests passed; a tier 1 lane that did
  #   not pass stops it. A tier 2 lane (the default) or a tier 3 one that
  #   did not pass is left out of it.
  RUNNERS = {
    "aarch64-apple-darwin" => { os: "macos-26", verify: "0", timeout: 150, build_timeout: 45, shards: 6, stage1: true, tier: 1 },
    "aarch64-linux-gnu" => { os: "ubuntu-24.04-arm", shards: 4, seconds: "180" },
    "aarch64-linux-musl" => { os: "ubuntu-24.04-arm", container: true, vendor: true, shards: 4, seconds: "180" },
    "x86_64-linux-gnu" => { os: "ubuntu-24.04", shards: 4, seconds: "180", tier: 1 },
    "x86_64-linux-musl" => { os: "ubuntu-24.04", container: true, shards: 2, seconds: "180" },
    "wasm32-wasi" => { os: "ubuntu-24.04-arm", host: "aarch64-linux-gnu", shards: 4, tier: 3 },
  }.freeze

  # The programs of a push: the cli tier and a slice where a libc, an ISA
  # or a link difference shows. Under wasmtime, the dispatch, Array and
  # Hash tests (1,196). Each module carried the whole runtime, which
  # wasmtime compiled again for each test, and they took 47 minutes; a
  # program module preloads the runtime, compiled once for the tier
  # (test/support/harness/wasmtime.rb), and 191 of them took under 3
  # minutes on 2 workers of a laptop.
  SLICE = "lang/methods,core/string"
  WASM_SLICE = "lang/methods,core/array,core/hash"

  module_function

  # Each lane, for a matrix of lane.yml.
  def matrix
    Zr::Target::ALL.map do |target|
      runner = RUNNERS.fetch(target.triple) { raise "no runner for #{target.triple}: add it to Lanes::RUNNERS" }
      shards = runner.fetch(:shards)
      { triple: target.triple, os: runner.fetch(:os), experimental: target.support == :experimental,
        container: runner.fetch(:container, false), jobs: runner.fetch(:jobs, ""), verify: runner.fetch(:verify, "1"),
        timeout: runner.fetch(:timeout, 90), build_timeout: runner.fetch(:build_timeout, 60), builds: [target.triple, *runner[:host]],
        slice: target.object_format == :wasm ? WASM_SLICE : SLICE, shards: (1..shards).to_a, of: shards,
        test_seconds: runner.fetch(:seconds, "60"), vendor: runner.fetch(:vendor, false), stage1: runner.fetch(:stage1, false),
        glibc: target.libc == :glibc, tier: runner.fetch(:tier, 2), gem_platform: target.gem_platform }
    end
  end

  def files = Dir[File.join(ROOT, "test/unit/*_test.rb")].sort

  # The unit files of the lane of `target`.
  def units(target)
    on_host = !RUNNERS.fetch(target.triple).fetch(:container, false) && !target.link.nil?
    files.select do |file|
      if Zr::Test::Needs.on(file).empty?
        on_host && Zr::Test::Needs.of(file) != :none
      else
        Zr::Test::Needs.on?(file, target)
      end
    end
  end

  # The unit files that name no kind of host and build no program.
  def untagged = files.select { |file| Zr::Test::Needs.on(file).empty? && Zr::Test::Needs.of(file) == :none }

  def relative(paths) = paths.map { |path| path.delete_prefix("#{ROOT}/") }
end

if $PROGRAM_NAME == __FILE__
  run = !ARGV.delete("--run").nil?
  if ARGV == ["matrix"]
    puts JSON.generate(Lanes.matrix)
    exit
  end
  files = case ARGV
          in ["units", triple] then Lanes.units(Zr::Target.fetch(triple) || abort("lanes: no target #{triple}"))
          in ["untagged"] then Lanes.untagged
          else abort "usage: ruby .github/scripts/lanes.rb matrix | units TRIPLE [--run] | untagged [--run]"
          end
  files = Lanes.relative(files)
  abort "lanes: no unit files" if files.empty?
  exec(File.join(Lanes::ROOT, "bin/minitest"), *files, chdir: Lanes::ROOT) if run
  puts files
end
