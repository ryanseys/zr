# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

ROOT = __dir__

# A tool runs under the checkout's own ruby, with the compiler and the
# test support on the load path, so a task never depends on how the
# shell was started.
def ruby_run(*args, env: {})
  sh(env, Gem.ruby, "-I#{File.join(ROOT, "lib")}", "-I#{File.join(ROOT, "test")}", *args)
end

def tool(name, *args, env: {}) = ruby_run(File.join(ROOT, "tools", "#{name}.rb"), *args, env: env)

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

desc "How long does what ze0 built take? rake 'bench[--runs 5 fib]'"
task(:bench, [:filters]) { |_, args| tool("bench", *args[:filters].to_s.split) }

desc "ze0 compiles itself twice, to the same bytes"
task(:stage1) { tool("stage1") }

desc "The compiler compiled by itself is a fixed point"
task(:stage2) { tool("stage2") }

# Every literal a spec asserts was lifted from a trailer ruby wrote, and
# this is what says it still is. It compiles nothing: each program is
# run under the ruby the `.ruby-version` pins and held to what its
# example claims.
desc "Every spec literal re-checked against ruby 4.0.6: rake 'oracle[test/spec/core/string]'"
task :oracle, [:path] do |_, args|
  tool("oracle", args[:path] || "test/spec")
end

# Each writes a file from an oracle: ruby, or a C source read at
# development time. The output carries a header saying so and is never
# edited by hand.
#
# `rt/ext/os/<os>/zr_description.rb` and `lib/ze0/obj/macho/libsystem.rb`
# are not here: they are snapshots the checks hold, and
# `ZE0_BLESS=1 rake test:unit FILTER=description` writes them again.
namespace :gen do
  # Tools that write their own files.
  WRITES = {
    features: "lib/ze0/hir/features.rb",
    cjk: "rt/core/cjk.rb",
    enc_mb: "rt/kernel/enc_mb.rb",
    nkf: "rt/ext/nkf/tables.rb",
    onig_unicode: "rt/core/regexp/unicode_tables.rb and rt/kernel/onig_tables.rb",
    onig_encodings: "rt/core/regexp/onig/encoding_tables.rb",
    prism_generate: "rt/ext/prism/ruby/*.rb",
    prism_encoding_tables: "rt/ext/prism/ruby/encoding_tables.rb",
    dispatch: "the programs that show which of its own methods a core class calls"
  }.freeze

  # Tools that write the file to stdout, so the task holds the pen.
  PRINTS = {
    unicode: "rt/core/unicode.rb",
    encodings: "rt/core/encodings.rb",
    transcode: "rt/core/transcode.rb",
    emoji: "rt/core/emoji.rb",
    builtin_lines: "rt/core/builtin_lines.rb",
    zlib_tables: "rt/kernel/zlib_tables.rb"
  }.freeze

  WRITES.each do |name, writes|
    desc "Write #{writes}"
    task(name) { tool(name.to_s) }
  end

  PRINTS.each do |name, writes|
    desc "Write #{writes}"
    task name do
      # The file is replaced only once the tool has written all of it: a
      # tool that stops half way leaves the old file standing.
      out = File.join(ROOT, writes)
      text = IO.popen([Gem.ruby, "-I#{File.join(ROOT, "lib")}", File.join(ROOT, "tools/#{name}.rb")], &:read)
      abort("rake gen:#{name}: the tool failed") unless $?.success?

      File.write(out, text)
      puts "wrote #{writes} (#{text.lines.size} lines)"
    end
  end

  desc "Write rt/ext/openssl/ossl/constants.rb"
  task :openssl_constants do
    out = File.join(ROOT, "rt/ext/openssl/ossl/constants.rb")
    text = IO.popen([Gem.ruby, File.join(ROOT, "tools/openssl/constants.rb")], &:read)
    abort("rake gen:openssl_constants: the tool failed") unless $?.success?

    File.write(out, text)
    puts "wrote rt/ext/openssl/ossl/constants.rb (#{text.lines.size} lines)"
  end
end

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

desc "Count the instructions the backend writes for the runtime"
task(:codesize, [:opts]) { |_, args| tool("codesize", *args[:opts].to_s.split) }

desc "Ask ruby what a whole program answers, and write it beside the program"
task(:record, [:program]) { |_, args| tool("record", *Array(args[:program])) }

task default: :test
