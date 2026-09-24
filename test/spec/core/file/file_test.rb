# frozen_string_literal: true

require "spec_helper"

describe "File programs" do
  it "glob keeps the pattern as written" do
    result = zr(<<~'RUBY')
      # A glob answers the pattern as it is written: a leading `./` stays on
      # every match, and so does a literal segment in the middle of it. A
      # pattern with no magic answers itself where the file is there.
      require "tmpdir"

      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write("thing.rb", "")
          Dir.mkdir("sub")
          File.write("sub/deep.rb", "")
          p Dir.glob("./*").sort
          p Dir["./*.rb"]
          p Dir.glob("./**/*.rb").sort
          p Dir.glob(".")
          p Dir.glob("./")
          p Dir.glob("*").sort
          p Dir.glob("./sub/../*").sort
          p Dir.glob("sub/*")
          p Dir.glob("./nope*")
          p Dir.glob("./sub/")
        end
      end

    RUBY

    _(result).must_answer <<~'OUT'
      ["./sub", "./thing.rb"]
      ["./thing.rb"]
      ["./sub/deep.rb", "./thing.rb"]
      ["."]
      ["./"]
      ["sub", "thing.rb"]
      ["./sub/../sub", "./sub/../thing.rb"]
      ["sub/deep.rb"]
      []
      ["./sub/"]
    OUT
  end

  it "path argument converts as ruby does" do
    result = zr(<<~'RUBY')
      # A path argument is a String, or what `to_path` or `to_str` answers,
      # and it may not hold a NUL byte (CRuby's rb_get_path). The environment
      # refuses NUL bytes in names and values the same way.
      require "pathname"

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue => e
        puts "#{label}: #{e.class}: #{e.message}"
      end

      show("exist? Pathname") { File.exist?(Pathname("no-such-file")) }
      show("exist? nil") { File.exist?(nil) }
      show("exist? Integer") { File.exist?(1) }
      show("exist? NUL") { File.exist?("a\0b") }
      show("file? Pathname") { File.file?(Pathname(__FILE__)) }
      show("directory? to_str") { o = Object.new; def o.to_str = "."; File.directory?(o) }
      show("readable? to_path") { o = Object.new; def o.to_path = __FILE__; File.readable?(o) }
      show("size NUL") { File.size("a\0b") }
      show("read NUL") { File.read("a\0b") }
      show("new nil") { File.new(nil) }
      show("stat NUL") { File.stat("a\0b") }
      show("Dir.exist? Pathname") { Dir.exist?(Pathname(".")) }
      show("Dir.entries NUL") { Dir.entries("a\0b") }
      show("basename Pathname") { File.basename(Pathname("x/y.rb")) }
      show("dirname Pathname") { File.dirname(Pathname("x/y.rb")) }
      show("extname Pathname") { File.extname(Pathname("x/y.rb")) }
      show("expand_path Pathname") { File.expand_path(Pathname("a"), Pathname("/tmp")) }
      show("basename nil") { File.basename(nil) }
      show("ENV NUL name") { ENV["a\0b"] = "1" }
      show("ENV NUL value") { ENV["ZR_NUL_CHECK"] = "a\0b" }
      show("ENV NUL read") { ENV["a\0b"] }
      show("ENV kept") { ENV.key?("ZR_NUL_CHECK") }

    RUBY

    _(result).must_answer <<~'OUT'
      exist? Pathname: false
      exist? nil: TypeError: no implicit conversion of nil into String
      exist? Integer: TypeError: no implicit conversion of Integer into String
      exist? NUL: ArgumentError: path name contains null byte
      file? Pathname: true
      directory? to_str: true
      readable? to_path: true
      size NUL: ArgumentError: path name contains null byte
      read NUL: ArgumentError: path name contains null byte
      new nil: TypeError: no implicit conversion of nil into String
      stat NUL: ArgumentError: path name contains null byte
      Dir.exist? Pathname: true
      Dir.entries NUL: ArgumentError: path name contains null byte
      basename Pathname: "y.rb"
      dirname Pathname: "x"
      extname Pathname: ".rb"
      expand_path Pathname: "/tmp/a"
      basename nil: TypeError: no implicit conversion of nil into String
      ENV NUL name: ArgumentError: bad environment variable name: contains null byte
      ENV NUL value: ArgumentError: bad environment variable value: contains null byte
      ENV NUL read: ArgumentError: bad environment variable name: contains null byte
      ENV kept: false
    OUT
  end

  it "stat names its device and lutime touches the link" do
    result = zr(<<~'RUBY')
      # A stat holds the device it was read from as one number, and names its
      # halves. A regular file has no device of its own, so both halves of
      # rdev are zero. lutime touches the link rather than what it points at,
      # and answers how many paths it touched.
      require "tmpdir"

      def t = yield rescue [$!.class, $!.message]

      Dir.mktmpdir do |dir|
        path = File.join(dir, "a")
        link = File.join(dir, "l")
        File.write(path, "x")
        File.symlink(path, link)

        st = File.stat(path)
        p st.dev_major.is_a?(Integer)
        p st.dev_minor.is_a?(Integer)
        p st.dev_major >= 0 && st.dev_minor >= 0
        p st.rdev_major, st.rdev_minor

        old = File.lstat(link).mtime
        p File.lutime(Time.at(1_000_000), Time.at(1_000_000), link)
        p File.lstat(link).mtime.to_i
        p File.stat(path).mtime.to_i == old.to_i || File.stat(path).mtime.to_i != 1_000_000
        p File.lutime(Time.at(2_000_000), Time.at(2_000_000), link, path)
        p File.stat(path).mtime.to_i
        # The message names the path, which is a different one every run.
        e = t { File.lutime(Time.now, Time.now, File.join(dir, "nope")) }
        p e.first, e.last.start_with?("No such file or directory @ apply2files - "), e.last.end_with?("/nope")
      end


    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      0
      0
      1
      1000000
      true
      2
      2000000
      Errno::ENOENT
      true
      true
    OUT
  end
end
