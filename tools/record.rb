# Asks ruby what an end-to-end program answers, and writes it beside
# the program.
#
#   rake 'record[e2e/core/io/stdout_flush_at_exit.rb]'
#   ruby tools/record.rb e2e/core/io/stdout_flush_at_exit.rb
#
# The answer is three files at most, each holding the bytes it holds and
# nothing else: `<name>.out` always, `<name>.err` when the program wrote
# to stderr, and `<name>.status` when it did not exit 0. There is no
# format to read and nothing to escape, so a wrong answer is a `diff`.
#
# ruby 4.0.6 is the only source of right answers, so this is the only
# thing that writes those files. A program already recorded is left
# alone: a change of answer is a change of program, and `--again` is how
# you say you meant it.
#
# A path is taken relative to `test/`, or as it stands when it already
# points into it.

require "open3"
require "rbconfig"
require_relative "../test/support/e2e"

ROOT = File.expand_path("../test", __dir__)

again = ARGV.delete("--again")
abort "usage: ruby tools/record.rb [--again] <program path>..." if ARGV.empty?

Dir.chdir(ROOT) do
  ARGV.each do |name|
    path = name.delete_prefix("#{ROOT}/").delete_prefix("test/")
    base = path.delete_suffix(".rb")
    abort "#{path}: no such program" unless File.file?(path)
    abort "#{path}: already recorded; say --again if you mean to replace it" if File.file?("#{base}.out") && !again

    how = Ze0::E2E::HOW.fetch(base.delete_prefix("e2e/"), {})
    stdin = how[:stdin] && File.binread(File.expand_path(how[:stdin], File.dirname(path)))
    # RUBYOPT is cleared: what the shell happens to carry must not reach
    # the answer a program is held to.
    env = how.fetch(:env, {}).merge("RUBYOPT" => nil)
    out, err, status = Open3.capture3(env, RbConfig.ruby, path, *Array(how[:argv]), stdin_data: stdin || "")

    File.binwrite("#{base}.out", out)
    %w[err status signal].each { |kind| File.delete("#{base}.#{kind}") if File.file?("#{base}.#{kind}") }
    File.binwrite("#{base}.err", err) unless err.empty?
    File.binwrite("#{base}.signal", "#{status.termsig}\n") if status.signaled?
    File.binwrite("#{base}.status", "#{status.exitstatus}\n") if !status.signaled? && !status.exitstatus.zero?

    wrote = Dir["#{base}.{out,err,status,signal}"].sort
    puts "recorded #{path} (#{status.signaled? ? "signal #{status.termsig}" : "exit #{status.exitstatus}"})"
    wrote.each { |f| puts "  #{f} (#{File.size(f)} bytes)" }
  end
end
