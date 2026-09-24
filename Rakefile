# frozen_string_literal: true

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
require "minitest/test_task"

ROOT = __dir__

# The task bodies live in `rakelib/*.rake`, which rake loads after this
# file, so what is here is what they share: the checkout's root, the
# load path the compiler and the test support want, and the collector
# tuning a compile wants.
$LOAD_PATH.unshift(File.join(ROOT, "lib"), File.join(ROOT, "test"))

# What `Zr::CLI.tune!` does to a command, without its re-exec, since a
# rake task cannot start itself again. A task that spawns a compile
# hands the tuning on through the environment, and the child then goes
# straight on rather than starting itself again.
def zr_tune!
  require "zr/cli"
  ENV.update(Zr::CLI::GC_ENV) if ENV["ZR_GC"] != "0" && !ENV.key?("RUBY_GC_MALLOC_LIMIT")
  RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable) && ENV["ZR_YJIT"] != "0"
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

# `TARGET=wasm32-wasi` builds every program for that triple and runs it
# the way that triple is run, as the cross-target rows of CI do;
# `GC=stress` collects at every allocation.
ENV["ZR_TARGET"] = ENV["TARGET"] if ENV["TARGET"]
# Every task runs the compiler under ruby unless the caller asks for the
# compiled one: the tiers, the bootstrap and `rake compile` measure and
# compare ruby's own road (lib/zr/self_host.rb).
ENV["ZR_SELF"] ||= "0"
ENV["ZR_GC_STRESS"] = "1" if ENV["GC"] == "stress"

# One tier: every file under `glob`, loaded into one process, which
# hands each example to a forked worker (`test/support/fork_pool.rb`).
#
# `Minitest::TestTask` is the front door, so a tier answers to
# minitest's own switches rather than to a language of ours: `N=/utf8/`
# runs the examples whose name matches, `X=` leaves some out, `A=-v`
# passes anything else through, and `MT_CPU=` says how many workers.
# It also defines `<tier>:slow` (the slowest 25), `<tier>:isolated`
# (which files fail when run alone) and `<tier>:cmd` beside each tier.
# The runtime a tier runs on is built ahead of time by `rake build`,
# once, on purpose: the runtime object, the prelinked image and the eval
# road for this host. A tier only asks whether they are there, and
# stops at once where one is not (`test/support/built.rb`). After an
# edit under `lib` or `rt`, `rake build` is what to reach for.
#
# wasm32-wasi is not this host's road and is built apart, by `rake
# build:wasm`: the unit files that build modules skip by name until it
# has run (`Checks.wasm_missing`), and `TARGET=wasm32-wasi` runs a tier
# for that triple.
#
# The asking runs in the tier's own process, ahead of its first fork,
# and loads what it finds: the runtime's description, its symbol table
# and the prelinked image, about as much again as the caches themselves.
# Every worker is a fork of that process, so all of them share one copy
# rather than reading and parsing it each.
def zr_ready_line(wasm: false) = %(require "support/built"; Zr::Test::Built.ready!(wasm: #{wasm}))

desc "Build the runtime for the checks on this host: its object, the prelinked image and the eval road"
task("build") { zr_build("Zr::Test::Built.targets") }

desc "Build the wasm32-wasi runtime and its preludes, for the checks that build modules"
task("build:wasm") { zr_build("[Zr::Target::WASM32_WASI]") }

desc "Build both: this host, then wasm32-wasi"
task("build:all") { zr_build("Zr::Test::Built.targets(wasm: true)") }

desc "Build the compiler with itself, which exe/zr then hands each build to while nothing under lib, rt or vendor changes"
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

# The tiers run under the collector tuning a build runs under
# (`CLI::GC_ENV`): a worker is a compiler, and it allocates as one. Set
# in this process, the tier's ruby inherits it. Measured over 510
# examples of three spec directories: 20.1 s -> 18.6 s.
alias zr_tuned zr_tune!

def tier(name, glob, framework, what, wasm: false)
  task("#{name}:tune") { zr_tuned }
  Minitest::TestTask.create(name) do |t|
    t.libs = %w[lib test]
    # The tests are the compiler's own Ruby, as `zr` itself is.
    t.test_prelude = "RubyVM::YJIT.enable; #{zr_ready_line(wasm: wasm)}"
    t.framework = %(require "#{framework}")
    t.test_globs = [File.join(ROOT, glob)]
    t.warning = false
  end
  # `<tier>:slow` as TestTask writes it reads minitest's own per-test
  # timings out of a verbose run, which the progress bar does not print
  # and which forked workers would interleave anyway. The reporter that
  # keeps the times reports by suite -- a file, in the spec tier -- and
  # keeps them between runs, so a file that has grown slower shows.
  Rake::Task["#{name}:slow"].clear
  desc "#{what} -- and which 25 files took the longest"
  task "#{name}:slow" do
    ENV["SLOW"] = "1"
    Rake::Task[name].invoke
  end

  # Rake joins descriptions rather than replacing them, so the generic
  # one TestTask wrote comes off before ours goes on.
  Rake::Task[name].clear_comments
  desc what
  task name => "#{name}:tune"
end

# `rake test test/unit/prism_test.rb` -- or a bare `prism_test.rb`, or a
# directory, or several of them. Rake reads every word after a task as
# another task, so a word that names something under `test/` is answered
# here with an empty task and collected instead, and `test` runs
# minitest over exactly those files rather than the three tiers.
#
# A word is only taken when it resolves INSIDE `test/`, so `N=/utf8/`,
# a switch, a bracketed argument and a real task name all go by
# untouched.
def zr_test_argv
  ARGV.drop(1).filter_map do |word|
    next if word.include?("=") || word.start_with?("-")

    full = File.expand_path(word, ROOT)
    full = Dir[File.join(ROOT, "test/**", word)].min unless File.exist?(full)
    found = full && File.exist?(full) && full.start_with?(File.join(ROOT, "test", ""))
    # A word that reads as a test path and names nothing stops the run.
    # Left alone it named no file, so `test` ran all three tiers before
    # rake found it had no such task -- and a CI step that lists a file
    # someone deleted would go on passing.
    abort "rake test: no test at #{word}" if !found && (word.start_with?("test/") || word.end_with?("_test.rb"))
    next unless found

    task(word) {} # so rake does not go looking for a task by this name
    full
  end
end

# The files a word names, and the helper the tier they live in loads.
def zr_test_files(paths)
  paths.flat_map { |p| File.directory?(p) ? Dir[File.join(p, "**/*_test.rb")].sort : [p] }
       .group_by { |f| f.start_with?(File.join(ROOT, "test/spec", "")) ? "spec_helper" : "test_helper" }
end

ZR_TEST_ARGV = zr_test_argv

desc "Where the tier running now stands, or the last one stood (tmp/test-progress.txt)"
task("test:progress") do
  require_relative "test/support/progress"
  puts(Zr::Test::Progress.read || "no tier has run yet")
end

desc "Every test: the units, the specs and the end-to-end programs"
if ZR_TEST_ARGV.empty?
  task test: %w[test:unit test:spec test:e2e]
else
  task :test do
    require "rbconfig"
    zr_tuned
    # The tier's own switches, so one file answers to what a whole tier
    # answers to: `N=` matches an example, `X=` leaves one out, `A=`
    # passes anything else through.
    opts = []
    opts += ["-n", ENV["N"]] if ENV["N"]
    opts += ["-e", ENV["X"]] if ENV["X"]
    opts += ENV["A"].split if ENV["A"]
    zr_test_files(ZR_TEST_ARGV).each do |framework, files|
      line = "RubyVM::YJIT.enable; #{zr_ready_line}; " + %(require "#{framework}"; ) +
             files.map { |f| %(require "#{f}"; ) }.join
      sh(RbConfig.ruby, "-Ilib:test", "-e", line, "--", *opts)
    end
  end
end

tier "test:unit", "test/unit/*_test.rb", "test_helper",
     "zr's own internals"
tier "test:spec", "test/spec/**/*_test.rb", "spec_helper",
     "Ruby held to ruby, program by program"
tier "test:e2e", "test/e2e/**/*_test.rb", "test_helper",
     "Whole programs through a real link"

task default: :test
