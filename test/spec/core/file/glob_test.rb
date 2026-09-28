# frozen_string_literal: true

require "spec_helper"

describe "Dir: glob" do
  it "glob walks depth first, sorts each directory, and shows the dot once" do
    result = zr(<<~'RUBY')
      # glob walks depth first and sorts each directory's names, and shows "."
      # only in the first directory it reads.
      require "tmpdir"
      require "fileutils"
      Dir.mktmpdir do |d|
        Dir.chdir(d) do
          %w[a/x a-b a.c A2 b/B/c .hid/q Z sub/.d sub/deep/e].each { |n| FileUtils.mkdir_p(File.dirname(n)); File.write(n, "") }
          p Dir.glob("**/*")
          p Dir.glob("**/*", File::FNM_DOTMATCH)
          p Dir.glob("sub/**/*", File::FNM_DOTMATCH), Dir.glob("*/*", File::FNM_DOTMATCH)
          p Dir.glob("**/.*"), Dir.glob("**/"), Dir.glob("sub/**/"), Dir.glob("sub/"), Dir.glob("sub//deep")
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["A2", "Z", "a", "a/x", "a-b", "a.c", "b", "b/B", "b/B/c", "sub", "sub/deep", "sub/deep/e"]
      [".", ".hid", ".hid/q", "A2", "Z", "a", "a/x", "a-b", "a.c", "b", "b/B", "b/B/c", "sub", "sub/.d", "sub/deep", "sub/deep/e"]
      ["sub/.", "sub/.d", "sub/deep", "sub/deep/e"]
      ["./.hid", "./A2", "./Z", "./a", "./a-b", "./a.c", "./b", "./sub", ".hid/q", "a/x", "b/B", "sub/.d", "sub/deep"]
      [".hid", "sub/.d"]
      ["a/", "b/", "b/B/", "sub/", "sub/deep/"]
      ["sub/", "sub/deep/"]
      ["sub/"]
      ["sub//deep"]
    OUT
  end

  it "glob expands braces without deduplication and reads a plain name's real case" do
    result = zr(<<~'RUBY')
      # Braces expand without deduplication, and one that never closes gives
      # nothing. A macOS volume matches names without their case, and a plain
      # name reads its real case back.
      require "tmpdir"
      Dir.mktmpdir do |d|
        Dir.chdir(d) do
          %w[a b sub].each { |n| File.write(n, "") }
          File.write("x}y", "")
          File.write("{a}", "")
          p Dir.glob("{a,a}"), Dir.glob("{b,a}"), Dir.glob("{a,b"), Dir.glob("x}y"), Dir.glob("\\{a}"), Dir.glob("{a\\,b}")
          p Dir.glob("A"), Dir.glob("S*"), Dir.glob("A", File::FNM_CASEFOLD)
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "a"]
      ["b", "a"]
      []
      ["x}y"]
      ["{a}"]
      []
      ["a"]
      ["sub"]
      ["a"]
    OUT
  end

  it "glob checks its options as dir_s_glob does" do
    result = zr(<<~'RUBY')
      # glob checks its options as dir_s_glob does.
      p((Dir.glob("*", sort: nil) rescue $!), (Dir.glob("*", "x") rescue $!), (Dir.glob("a\0b") rescue $!), (Dir.glob(1) rescue $!))
      p Dir.glob("*", base: "").class, (Dir.glob("a".encode("utf-16le")) rescue $!)
    RUBY

    _(result).must_answer <<~'OUT'
      #<ArgumentError: expected true or false as sort: nil>
      #<TypeError: no implicit conversion of String into Integer>
      #<ArgumentError: nul-separated glob pattern is deprecated>
      #<TypeError: no implicit conversion of Integer into String>
      Array
      #<Encoding::CompatibilityError: incompatible character encodings: UTF-16LE and US-ASCII>
    OUT
  end
end
