# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../../lib/zr/tar"

# The ustar archive of a runtime bundle (lib/zr/tar.rb).
class TarTest < Minitest::Test
  Tar = Zr::Tar

  def archive(files)
    io = StringIO.new(+"".b)
    files.each { |name, bytes| Tar.add(io, name, bytes.bytesize) { |out| out.write(bytes) } }
    Tar.finish(io)
    io.string
  end

  def entries(bytes, read: true)
    io = StringIO.new(bytes)
    got = []
    Tar.each(io) { |name, size| got << [name, read ? io.read(size) : size] }
    got
  end

  # A name past 100 bytes goes in the prefix field, as `tar` reads it.
  def test_files_come_back_in_order_with_long_names
    long = "store/code/9f/#{"a" * 64}/#{"b" * 60}.pack"
    files = [["manifest.json", "{}"], [long, "x" * 700], ["empty", ""]]

    assert_equal files, entries(archive(files))
    assert_equal 0, archive(files).bytesize % Tar::BLOCK
  end

  def test_an_unread_file_is_skipped
    files = [["a", "1" * 600], ["b", "2"]]

    assert_equal [["a", 600], ["b", 1]], entries(archive(files), read: false)
  end

  def test_the_same_files_give_the_same_bytes
    assert_equal archive([["a", "1"]]), archive([["a", "1"]])
  end

  def test_a_truncated_or_changed_archive_is_refused
    bytes = archive([["a", "1" * 600]])

    assert_raises(Tar::Truncated) { entries(bytes[0, 700]) }
    changed = bytes.dup
    changed[0] = "z"
    assert_raises(ArgumentError) { entries(changed) }
  end

  def test_a_name_that_no_header_holds_is_refused
    assert_raises(Tar::TooLong) { archive([["#{"d" * 160}/#{"f" * 20}", ""]]) }
    assert_raises(Tar::TooLong) { archive([["d/#{"f" * 120}", ""]]) }
  end
end
