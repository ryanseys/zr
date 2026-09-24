# frozen_string_literal: true

# Runs an end-to-end program with ruby, and writes the output next to
# the program.
#
#   rake 'record[e2e/core/io/stdout_flush_at_exit.rb]'
#   rake 'record[--again e2e/core/io/stdout_flush_at_exit.rb]'
#
# The recording has at most four files, and each contains only the raw
# bytes: `<name>.out` always, `<name>.err` when the program wrote to
# stderr, `<name>.status` when it did not exit 0, and `<name>.signal`
# when a signal stopped it. There is no format and no escaping, so
# `diff` shows an incorrect output.
#
# Ruby 4.0.6 is the only reference for correct output, so only this task
# writes these files. It does not replace an existing recording: a new
# output needs a changed program. Use `--again` to replace it.
#
# A path is relative to `test/`, or used as given when it already starts
# with `test/`. A benchmark path is `benchmark/<name>.rb`; it runs from
# the repository root, as `rake bench` runs it.

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
    # Clear RUBYOPT, so that the shell's settings do not change the
    # recorded output.
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
