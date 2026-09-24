# frozen_string_literal: true

# Asks ruby what an end-to-end program answers, and writes it beside
# the program.
#
#   rake 'record[e2e/core/io/stdout_flush_at_exit.rb]'
#   rake 'record[--again e2e/core/io/stdout_flush_at_exit.rb]'
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
# points into it; a benchmark is named as `benchmark/<name>.rb`, and is
# run from the repository's root, where `rake bench` runs it.

require "open3"
require "rbconfig"
require_relative "../test/support/e2e"

module Record
  REPO = File.expand_path("..", __dir__)
  ROOT = File.join(REPO, "test")

  module_function

  def write(argv)
    again = argv.delete("--again")
    abort "usage: rake 'record[[--again] <program path>...]'" if argv.empty?

    argv.each do |name|
      name = name.delete_prefix("#{REPO}/")
      if name.start_with?("benchmark/")
        Dir.chdir(REPO) { one(name, again) }
      else
        Dir.chdir(ROOT) { one(name.delete_prefix("test/"), again) }
      end
    end
  end

  def one(path, again)
    base = path.delete_suffix(".rb")
    abort "#{path}: no such program" unless File.file?(path)
    abort "#{path}: already recorded; say --again if you mean to replace it" if File.file?("#{base}.out") && !again

    how = Zr::E2E::HOW.fetch(base.delete_prefix("e2e/"), {})
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

    puts "recorded #{path} (#{status.signaled? ? "signal #{status.termsig}" : "exit #{status.exitstatus}"})"
    Dir["#{base}.{out,err,status,signal}"].sort.each { |f| puts "  #{f} (#{File.size(f)} bytes)" }
  end
end

desc "Ask ruby what a whole program answers, and write it beside the program"
task(:record, [:program]) { |_, args| Record.write(args[:program].to_s.split) }
