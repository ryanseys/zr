# frozen_string_literal: true

# Runs ruby 4.0.6's own openssl tests (test/openssl at revision
# 03b6d3f) on ruby itself with the port in place of the C extension
# (tools/openssl/host.rb), and without it with --ruby, which is how the
# tests answer against the extension.
#
#   ruby tools/openssl/suite.rb                  # every file
#   ruby tools/openssl/suite.rb digest hmac      # test_digest.rb, test_hmac.rb
#   ruby tools/openssl/suite.rb ssl -- -n /session/  # arguments for test/unit
#
# The tests come out of the ruby checkout at RUBY_SRC (default
# ~/dev/github.com/ruby/ruby) into tmp/openssl-suite, once. Three files
# run at a time; each has a time limit.
require "fileutils"
require "open3"
require "rbconfig"

ROOT = File.expand_path("../..", __dir__)
REVISION = "03b6d3f8898a"
SUITE = File.join(ROOT, "tmp/openssl-suite")
SOURCE = ENV.fetch("RUBY_SRC", File.expand_path("~/dev/github.com/ruby/ruby"))
LIMIT = 600

argv = ARGV.dup
extra = (i = argv.index("--")) ? argv.slice!(i..)[1..] : []
native = argv.delete("--ruby")
verbose = argv.delete("--verbose")

unless File.exist?(File.join(SUITE, "test/openssl/utils.rb"))
  FileUtils.mkdir_p(SUITE)
  archive = IO.popen(["git", "-C", SOURCE, "archive", REVISION, "test/openssl", "tool/lib"], &:read)
  abort "git archive failed in #{SOURCE}" unless $?.success?
  IO.popen(["tar", "x", "-C", SUITE], "w") { |tar| tar.write(archive) }
end

dir = File.join(SUITE, "test/openssl")
files = Dir[File.join(dir, "test_*.rb")].sort
files = files.select { |file| argv.any? { |name| File.basename(file, ".rb").delete_prefix("test_") == name } } unless argv.empty?
abort "no test file matches #{argv.join(" ")}" if files.empty?

env = native ? {} : { "RUBYOPT" => "-r#{File.join(ROOT, "tools/openssl/host.rb")}" }
results = Queue.new
files.each { |file| results << file }
rows = {}
workers = Array.new(3) do
  Thread.new do
    while (file = begin; results.pop(true); rescue ThreadError; nil; end)
      command = [RbConfig.ruby, "-I", File.join(SUITE, "tool/lib"), file, *extra]
      output, status = Open3.capture2e(env, "timeout", LIMIT.to_s, *command, chdir: dir)
      summary = output.lines.grep(/\d+ tests, \d+ assertions/).last&.strip || "no summary (exit #{status.exitstatus})"
      rows[file] = [summary, output]
    end
  end
end
workers.each(&:join)

failed = 0
files.each do |file|
  summary, output = rows.fetch(file)
  bad = !summary.match?(/ 0 failures, 0 errors/)
  failed += 1 if bad
  puts format("%-28s %s", File.basename(file, ".rb"), summary)
  puts output.lines.reject { |l| l.start_with?("Run options", "# Running", "Finished tests") }.join.gsub(/^/, "    ") if bad || verbose
end
exit(failed.zero? ? 0 : 1)
