# frozen_string_literal: true

require "open3"
require_relative "lib/zr/dev"
require_relative "../test/support/harness/reference"

module Zr
  module Dev
    # Runs a benchmark with ruby, and writes the output next to it.
    #
    #   zr-dev record benchmark/bm_so_lists.rb
    #   zr-dev record --again benchmark/bm_so_lists.rb
    #
    # The recording has at most four files, and each contains only the
    # raw bytes: `<name>.out` always, `<name>.err` when the program wrote
    # to stderr, `<name>.status` when it did not exit 0, and
    # `<name>.signal` when a signal stopped it. There is no format and no
    # escaping, so `diff` shows an incorrect output. `zr-dev bench` reads
    # them (`Harness::Answer.beside`). The program tests have their own
    # files and tool (`zr-dev expect`).
    #
    # Ruby 4.0.7 is the only reference for correct output, so only this
    # tool writes these files. It does not replace an existing recording:
    # a new output needs a changed program. Use `--again` to replace it.
    # A benchmark runs from the repository root, as `zr-dev bench` runs it.
    class Record < Command
      summary "Ask ruby what a benchmark answers, and write it beside the benchmark"
      usage "[--again] <benchmark>..."
      host_ruby!

      def defaults = @again = false

      def options(o) = o.on("--again", "replace an existing recording") { @again = true }

      def run(argv)
        fail!("give the path of a benchmark") if argv.empty?

        argv.each do |name|
          name = Dev.rel(File.expand_path(name))
          fail!("#{name}: not a benchmark; `zr-dev expect` writes a program test's files") unless name.start_with?("benchmark/")

          Dir.chdir(ROOT) { one(name) }
        end
      end

      def one(path)
        base = path.delete_suffix(".rb")
        fail!("#{path}: no such program") unless File.file?(path)
        fail!("#{path}: already recorded; say --again if you mean to replace it") if File.file?("#{base}.out") && !@again

        # Clear RUBYOPT, so that the shell's settings do not change the
        # recorded output.
        env = Harness::Reference.env.merge("RUBYOPT" => nil)
        out, err, status = Open3.capture3(env, Dev.ruby, path, stdin_data: "")
        File.binwrite("#{base}.out", out)
        %w[err status signal].each { |kind| File.delete("#{base}.#{kind}") if File.file?("#{base}.#{kind}") }
        File.binwrite("#{base}.err", err) unless err.empty?
        File.binwrite("#{base}.signal", "#{status.termsig}\n") if status.signaled?
        File.binwrite("#{base}.status", "#{status.exitstatus}\n") if !status.signaled? && !status.exitstatus.zero?

        puts "recorded #{path} (#{status.signaled? ? "signal #{status.termsig}" : "exit #{status.exitstatus}"})"
        Dir["#{base}.{out,err,status,signal}"].sort.each { |f| puts "  #{f} (#{File.size(f)} bytes)" }
      end
    end
  end
end
