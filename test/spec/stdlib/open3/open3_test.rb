# frozen_string_literal: true

require "spec_helper"

describe "Open3 programs" do
  it "spawn takes the pipe ends popen2 and popen3 build, and the wait thread carries the status" do
    result = ze0(<<~'RUBY')
      # Open3 over the real spawn machinery: Kernel#spawn taking IO redirect
      # targets (the pipe ends popen2/popen3 build), plus Process.detach's wait
      # thread carrying the child's Process::Status.
      require "open3"

      out, status = Open3.capture2("echo", "hi")
      p out
      p status.exitstatus

      out, err, status = Open3.capture3("sh", "-c", "echo to-out; echo to-err >&2; exit 3")
      p out
      p err
      p status.exitstatus

      Open3.popen2("cat") do |stdin, stdout, wait_thr|
        stdin.puts "through the pipes"
        stdin.close
        p stdout.read
        p wait_thr.value.success?
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "hi\n"
      0
      "to-out\n"
      "to-err\n"
      3
      "through the pipes\n"
      true
    OUT
  end

  it "the vendored gem loads with its JRuby-only require pruned rather than spliced" do
    result = ze0(<<~'RUBY')
      # open3's last line is `require 'open3/jruby_windows' if RUBY_ENGINE ==
      # 'jruby' && ...`; that file is JRuby-native (`require 'jruby'`, java_import)
      # and must be pruned rather than spliced. Loading open3 and reflecting on
      # its API needs no subprocess, so this exercises the load path end-to-end.

      require "open3"
      puts Open3.respond_to?(:capture3)
      puts Open3.respond_to?(:popen3)
    RUBY

    _(result).must_answer "true\ntrue\n"
  end
end
