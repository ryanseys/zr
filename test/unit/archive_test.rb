# frozen_string_literal: true

require "test_helper"
require "rbconfig"
require_relative "../../lib/zr/obj/archive"

# Checks `Obj::Archive`, zr's reader of static libraries, against `nm`,
# over the archives that the host ruby installs (libz, libffi, libyaml,
# libssl, libcrypto).
class ArchiveTest < Minitest::Test
  Archive = Zr::Obj::Archive

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
  end

  def archives
    found = Dir[File.join(RbConfig::CONFIG["libdir"], "*.a")].reject { |path| path.include?("libruby") }.sort
    skip "the host ruby has no static libraries" if found.empty?
    found
  end

  # `nm --print-armap`'s map: `symbol in member` lines, before the first
  # blank line.
  def nm_index(path)
    lines = IO.popen(["nm", "--print-armap", path], err: File::NULL, &:read).lines.map(&:chomp)
    lines.drop(1).take_while { |line| !line.empty? }.map { |line| line.split(" in ", 2) }.sort
  end

  def test_the_index_is_the_one_that_nm_prints
    archives.each do |path|
      archive = Archive.read(File.binread(path))
      ours = archive.index.flat_map { |symbol, member| [[symbol, member.name]] }.sort
      assert_equal nm_index(path).uniq { |symbol, _| symbol }.sort, ours, "index of #{path}"
    end
  end

  def test_each_member_is_an_arm64_object
    archives.each do |path|
      Archive.read(File.binread(path)).members.each do |member|
        assert_equal [0xFEEDFACF, 0x0100000C, 1], member.bytes.unpack("L<2x4L<"), "#{member.name} of #{path}"
      end
    end
  end

  def test_needed_takes_the_members_that_define_what_is_needed_and_what_they_need
    path = archives.find { |a| File.basename(a) == "libz.a" } || skip("the host ruby has no libz.a")
    archive = Archive.read(File.binread(path))
    names = archive.needed(["_deflate"]).map(&:name)
    assert_includes names, "deflate.o"
    assert_includes names, "trees.o", "deflate.o calls _tr_flush_block, which trees.o defines"
    refute_includes names, "inflate.o"
    assert_empty archive.needed(["_not_in_the_archive"])
  end

  def test_a_file_that_is_not_an_archive_is_refused
    assert_raises(ArgumentError) { Archive.read("\x7FELF".b) }
  end
end
