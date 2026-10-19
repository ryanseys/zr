# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr/embedded_files"

# `EmbeddedFiles`: the files that a library reads by a path from its own
# directory go into the binary as bytes; reads that name another file, or
# a file outside the library roots, still read the disk.
class EmbeddedFilesTest < Minitest::Test
  def library(dir, source)
    lib = File.join(dir, "lib")
    FileUtils.mkdir_p(File.join(lib, "mylib"))
    File.write(File.join(lib, "mylib/data.txt"), "data\n")
    File.write(File.join(lib, "mylib/other.rb"), "1\n")
    path = File.join(lib, "mylib.rb")
    File.write(path, source)
    [lib, path]
  end

  def test_a_read_through_a_local_set_from_the_files_directory_is_carried
    Dir.mktmpdir do |dir|
      lib, path = library(dir, <<~RUBY)
        path = File.join(__dir__, "mylib/data.txt")
        eval File.read(path), nil, path
      RUBY

      assert_equal({ File.join(lib, "mylib/data.txt") => "data\n" }, Zr::EmbeddedFiles.for([path], [lib]))
    end
  end

  def test_each_read_form_and_expand_path_from_the_directory_is_carried
    Dir.mktmpdir do |dir|
      lib, path = library(dir, <<~RUBY)
        IO.readlines(File.expand_path("mylib/data.txt", __dir__))
        File.binread("\#{__dir__}/mylib/other.rb")
      RUBY

      assert_equal %w[mylib/data.txt mylib/other.rb], Zr::EmbeddedFiles.for([path], [lib]).keys.map { |file| file.delete_prefix("#{lib}/") }.sort
    end
  end

  def test_a_bare_literal_a_reassigned_local_and_a_file_outside_the_roots_stay_on_disk
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "outside.txt"), "x")
      lib, path = library(dir, <<~RUBY)
        File.read("/etc/hosts")
        path = File.join(__dir__, "mylib/data.txt")
        path = ENV["X"]
        File.read(path)
        File.read(File.join(__dir__, "../outside.txt"))
        File.read(File.join(__dir__, "mylib/missing.txt"))
      RUBY

      assert_empty Zr::EmbeddedFiles.for([path], [lib])
      assert_empty Zr::EmbeddedFiles.for([path], [File.join(dir, "elsewhere")]), "a file outside the roots is not scanned"
    end
  end
end
