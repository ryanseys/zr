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

desc "Every test: the units, the specs and the end-to-end programs"
task test: %w[test:unit test:spec test:e2e]

tier "test:unit", "test/unit/*_test.rb", "test_helper",
     "ze0's own internals"
tier "test:spec", "test/spec/**/*_test.rb", "spec_helper",
     "Ruby held to ruby, program by program"
tier "test:e2e", "test/e2e/**/*_test.rb", "test_helper",
     "Whole programs through a real link"

# Each runs a Ruby port and ruby's own implementation on the host, and
# compares the two. They are where a port is developed; the checks hold
# the same ports to a fixed sample.
namespace :diff do
  { prism: "the prism port with ruby's prism",
    regexp: "the Onigmo port with ruby's regexp engine",
    zlib: "the zlib port with ruby's zlib, byte for byte",
    ast: "rt/ext/ze0/ast.rb with ruby's RubyVM::AbstractSyntaxTree" }.each do |name, what|
    desc "Hold #{what}: rake 'diff:#{name}[--fuzz 100]'"
    task(name, [:opts]) { |_, args| tool("#{name}_diff", *args[:opts].to_s.split) }
  end

  desc "Run prism 1.9.0's own test suite on the port"
  task(:prism_upstream, [:opts]) { |_, args| tool("prism_upstream_tests", *args[:opts].to_s.split) }

  desc "Run ruby 4.0.6's test/openssl against the port"
  task(:openssl, [:opts]) { |_, args| ruby_run(File.join(ROOT, "tools/openssl/suite.rb"), *args[:opts].to_s.split) }
end

task default: :test
