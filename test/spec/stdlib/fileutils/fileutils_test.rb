# frozen_string_literal: true

require "spec_helper"

describe "FileUtils programs" do
  it "the vendored gem compiles from its upstream source, and the core file operations answer" do
    result = zr(<<~'RUBY')
      # FileUtils -- the vendored pure-Ruby stdlib gem (gems/fileutils), compiled
      # from its real upstream source, not reimplemented. Exercises the core file
      # operations rubygems/bundler rely on; every line is oracle-matched.
      require "fileutils"

      puts FileUtils::VERSION
      puts FileUtils.respond_to?(:mkdir_p)

      d = "/tmp/zr_fileutils_example"
      FileUtils.rm_rf(d) # a clean slate, idempotent across runs

      FileUtils.mkdir_p("#{d}/a/b/c")
      puts Dir.exist?("#{d}/a/b/c")

      File.write("#{d}/a/src.txt", "hello")
      FileUtils.cp("#{d}/a/src.txt", "#{d}/a/copy.txt")
      puts File.read("#{d}/a/copy.txt")

      FileUtils.mv("#{d}/a/copy.txt", "#{d}/a/moved.txt")
      puts File.exist?("#{d}/a/moved.txt")
      puts File.exist?("#{d}/a/copy.txt")

      FileUtils.touch("#{d}/a/t.txt")
      puts File.exist?("#{d}/a/t.txt")

      FileUtils.rm_rf(d)
      puts Dir.exist?(d)
    RUBY

    _(result).must_answer <<~'OUT'
      1.8.0
      true
      true
      hello
      true
      false
      true
      false
    OUT
  end

  it "mkdir_p, cp, mv, rm_rf and their siblings all run out of the gem the lock resolves" do
    result = zr(<<~'RUBY', files: {"fileutils.rb" => fixture("stdlib/fileutils/fileutils.rb")})
      # `require "fileutils"` compiles the real upstream gem the lock resolves,
      # including its load-time module metaprogramming (module_function, extend
      # self, class << self, a platform-conditional StreamUtils_), and the core
      # file operations bundler relies on work.

      require "fileutils"
      puts FileUtils::VERSION
      puts FileUtils.respond_to?(:mkdir_p)
      d = "/tmp/zr_fu_e2e_#{Process.pid}"
      FileUtils.rm_rf(d)
      FileUtils.mkdir_p("#{d}/a/b")
      puts Dir.exist?("#{d}/a/b")
      File.write("#{d}/a/f", "hi")
      FileUtils.cp("#{d}/a/f", "#{d}/a/g")
      puts File.read("#{d}/a/g")
      FileUtils.mv("#{d}/a/g", "#{d}/a/h")
      puts File.exist?("#{d}/a/h")
      FileUtils.rm_rf(d)
      puts Dir.exist?(d)
    RUBY

    _(result).must_answer <<~'OUT'
      1.8.0
      true
      true
      hi
      true
      false
    OUT
  end
end
