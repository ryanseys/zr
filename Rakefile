# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

ROOT = __dir__

# The task bodies live in `rakelib/*.rake`, which rake loads after this
# file, so what is here is what they share: the checkout's root, the
# load path the compiler and the test support want, and the collector
# tuning a compile wants.
$LOAD_PATH.unshift(File.join(ROOT, "lib"), File.join(ROOT, "test"))

# What `Ze0::CLI.tune!` does to a command, without its re-exec, since a
# rake task cannot start itself again. A task that spawns a compile
# hands the tuning on through the environment, and the child then goes
# straight on rather than starting itself again.
def ze0_tune!
  require "ze0/cli"
  ENV.update(Ze0::CLI::GC_ENV) if ENV["ZE0_GC"] != "0" && !ENV.key?("RUBY_GC_MALLOC_LIMIT")
  RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable) && ENV["ZE0_YJIT"] != "0"
end

# A generated file, written whole: the task prints into a string and the
# file is replaced only once all of it is there, so a generator that
# stops half way leaves the old file standing.
def ze0_write(path)
  require "stringio"
  io = StringIO.new
  yield io
  File.write(File.join(ROOT, path), io.string)
  puts "wrote #{path} (#{io.string.lines.size} lines)"
end

# `TARGET=wasm32-wasi` builds every program for that triple and runs it
# the way that triple is run, as the cross-target rows of CI do;
# `GC=stress` collects at every allocation.
ENV["ZE0_TARGET"] = ENV["TARGET"] if ENV["TARGET"]
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
def tier(name, glob, framework, what)
  Minitest::TestTask.create(name) do |t|
    t.libs = %w[lib test]
    # The tests are the compiler's own Ruby, as `ze0` itself is.
    t.test_prelude = %(RubyVM::YJIT.enable)
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
  task name
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
def ze0_test_argv
  ARGV.drop(1).filter_map do |word|
    next if word.include?("=") || word.start_with?("-")

    full = File.expand_path(word, ROOT)
    full = Dir[File.join(ROOT, "test/**", word)].min unless File.exist?(full)
    next unless full && File.exist?(full) && full.start_with?(File.join(ROOT, "test", ""))

    task(word) {} # so rake does not go looking for a task by this name
    full
  end
end

# The files a word names, and the helper the tier they live in loads.
def ze0_test_files(paths)
  paths.flat_map { |p| File.directory?(p) ? Dir[File.join(p, "**/*_test.rb")].sort : [p] }
       .group_by { |f| f.start_with?(File.join(ROOT, "test/spec", "")) ? "spec_helper" : "test_helper" }
end

ZE0_TEST_ARGV = ze0_test_argv

desc "Every test: the units, the specs and the end-to-end programs"
if ZE0_TEST_ARGV.empty?
  task test: %w[test:unit test:spec test:e2e]
else
  task :test do
    require "rbconfig"
    # The tier's own switches, so one file answers to what a whole tier
    # answers to: `N=` matches an example, `X=` leaves one out, `A=`
    # passes anything else through.
    opts = []
    opts += ["-n", ENV["N"]] if ENV["N"]
    opts += ["-e", ENV["X"]] if ENV["X"]
    opts += ENV["A"].split if ENV["A"]
    ze0_test_files(ZE0_TEST_ARGV).each do |framework, files|
      line = %(RubyVM::YJIT.enable; require "#{framework}"; ) +
             files.map { |f| %(require "#{f}"; ) }.join
      sh(RbConfig.ruby, "-Ilib:test", "-e", line, "--", *opts)
    end
  end
end

tier "test:unit", "test/unit/*_test.rb", "test_helper",
     "ze0's own internals"
tier "test:spec", "test/spec/**/*_test.rb", "spec_helper",
     "Ruby held to ruby, program by program"
tier "test:e2e", "test/e2e/**/*_test.rb", "test_helper",
     "Whole programs through a real link"

task default: :test
