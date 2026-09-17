# frozen_string_literal: true

require "bundler/gem_tasks"

ROOT = __dir__

# A tool runs under the checkout's own ruby, with the compiler and the
# test support on the load path, so a task never depends on how the
# shell was started.
def ruby_run(*args, env: {})
  sh(env, Gem.ruby, "-I#{File.join(ROOT, "lib")}", "-I#{File.join(ROOT, "test")}", *args)
end

def tool(name, *args, env: {}) = ruby_run(File.join(ROOT, "tools", "#{name}.rb"), *args, env: env)

def supervise(glob, env: {})
  require_relative "test/support/supervisor"
  files = Dir[File.join(ROOT, glob)].sort
  filter = ENV["FILTER"].to_s.split
  files = files.select { |f| filter.any? { |a| File.basename(f).include?(a) } } unless filter.empty?
  abort("rake: nothing matches #{filter.join(" ")}") if files.empty?
  Ze0::Test::Supervisor.new(ROOT, env: env).run(files) or exit(1)
end

desc "Every test: the units, the specs and the end-to-end programs"
task test: %w[test:unit test:spec test:e2e]

namespace :test do
  desc "ze0's own internals; FILTER=exe,zr picks files"
  task :unit do
    supervise("test/unit/*_test.rb")
  end

  desc "Ruby held to ruby, program by program; FILTER= picks files, GC=stress collects at every allocation"
  task :spec do
    next puts("rake test:spec: no specs yet") if Dir[File.join(ROOT, "test/spec/**/*_test.rb")].empty?

    supervise("test/spec/**/*_test.rb", env: ENV["GC"] == "stress" ? { "ZR_GC_STRESS" => "1" } : {})
  end

  desc "Whole programs through a real link"
  task :e2e do
    next puts("rake test:e2e: no programs yet") if Dir[File.join(ROOT, "test/e2e/**/*.rb")].empty?

    supervise("test/e2e/**/*_test.rb")
  end

  desc "One file, with minitest's own options: rake 'test:one[test/unit/zr_test.rb,-n /gc/]'"
  task :one, [:file, :opts] do |_, args|
    abort("rake test:one: name a file") unless args[:file]
    ruby_run("--yjit", args[:file], *args[:opts].to_s.split)
  end
end

desc "How long does what ze0 built take?"
task :bench, [:filters] do |_, args|
  ruby_run(File.join(ROOT, "bin/ze0"), "bench", *args[:filters].to_s.split)
end

desc "ze0 compiles itself twice, to the same bytes"
task(:stage1) { ruby_run(File.join(ROOT, "bin/ze0"), "stage1") }

desc "The compiler compiled by itself is a fixed point"
task(:stage2) { ruby_run(File.join(ROOT, "bin/ze0"), "stage2") }

# Every literal a spec asserts was lifted from a trailer ruby wrote, and
# this is what says it still is.
desc "Every spec literal re-checked against ruby 4.0.6"
task :oracle do
  abort("rake oracle: not written until the first area converts")
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

# The OS tables come from the ruby of the OS they describe
# (tools/layer.rb), so this runs on each OS's own ruby: darwin here, an
# Alpine ruby for linux. socket's table follows ruby's own list of names,
# which lives in ruby's source rather than in any install.
desc "Write this OS's tables again and fail on a difference: MKCONSTANTS=<ruby>/ext/socket/mkconstants.rb rake tables"
task :tables do
  mkconstants = ENV.fetch("MKCONSTANTS") { abort "rake tables: MKCONSTANTS names ruby 4.0.6's ext/socket/mkconstants.rb" }
  %w[errno fcntl etc].each { |name| tool(name) }
  tool("socket", mkconstants)
  os = RUBY_PLATFORM[/darwin|linux|wasi/]
  sh("git", "diff", "--exit-code", "--", "rt/core/os/#{os}", "rt/ext/os/#{os}")
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

# A program ze0 does not answer yet lives in test/gaps/, and comes back
# the day it does.
namespace :gaps do
  desc "Move a case ze0 no longer matches into test/gaps/"
  task(:demote, [:case]) { |_, args| tool("gap", *Array(args[:case])) }

  desc "Move a gap that matches back to its topic"
  task(:promote, [:case, :dir]) { |_, args| tool("gap", "--promote", args[:case], *Array(args[:dir])) }

  desc "Move every defect row of a sweep into test/gaps/"
  task(:sweep) { tool("gap", "--sweep", File.join(ROOT, "tmp/sweep.txt")) }
end

desc "Count the instructions the backend writes for the runtime"
task(:codesize, [:opts]) { |_, args| tool("codesize", *args[:opts].to_s.split) }

desc "Record ruby's answer under __END__ for an end-to-end program"
task(:record, [:case]) { |_, args| tool("record", *Array(args[:case])) }

task default: :test
