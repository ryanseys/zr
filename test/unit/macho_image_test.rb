# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/obj/macho/image"
require_relative "../support/harness/reference"

# Checks `Obj::MachO::Image`, zr's reader of linked Mach-O images, against
# the tools that read them for Apple: `nm` for the symbols, `otool -l` for
# the segments and `dyld_info -fixups` for each pointer that dyld fixes.
# The images are the C extensions that ruby and the reference gems
# hold, so the reader sees the bundles that zr will link and load.
class MachOImageTest < Minitest::Test
  Image = Zr::Obj::MachO::Image

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
  end

  # Every C extension bundle of the host ruby and the reference gems.
  def self.bundles
    roots = [Gem.default_dir, Zr::Harness::Reference::GEMS]
    roots.flat_map { |root| Dir[File.join(root, "{extensions,gems}", "**", "*.bundle")] }
         .reject { |path| path.include?(".dSYM/") }.uniq.sort
  end

  def bundles
    found = self.class.bundles
    skip "no C extension bundles are installed" if found.empty?
    found
  end

  def tool(*argv) = IO.popen(argv, err: File::NULL, &:read)

  def test_the_symbols_are_those_that_nm_lists
    bundles.each do |path|
      image = Image.read(File.binread(path))
      assert_equal tool("nm", "-u", path).split.sort, image.undefined, "undefined symbols of #{path}"
      assert_equal tool("nm", "-gU", path).lines.map { |l| l.split.last }.sort, image.defined, "defined symbols of #{path}"
    end
  end

  def test_the_segments_are_those_that_otool_lists
    bundles.each do |path|
      image = Image.read(File.binread(path))
      listed = tool("otool", "-l", path).scan(/cmd LC_SEGMENT_64.*?segname (\S+)\s+vmaddr (0x\h+)\s+vmsize (0x\h+)/m)
      expected = listed.map { |name, addr, size| [name, Integer(addr), Integer(size)] }
      assert_equal expected, image.segments.map { |s| [s.name, s.vmaddr, s.vmsize] }, "segments of #{path}"
    end
  end

  def test_each_fixup_is_one_that_dyld_info_lists
    bundles.each do |path|
      image = Image.read(File.binread(path))
      ours = image.rebases.map { |r| [r.address, "rebase", format("0x%08X", r.target)] } +
             image.binds.map { |b| [b.address, b.lazy ? "lazy-bind" : "bind", bind_target(image, b)] }
      theirs = dyld_fixups(path)
      # dyld_info lists a weak definition (the weak bind stream) as a bind
      # with the name of an unrelated import; zr keeps them as weak_binds.
      coalesced = image.weak_binds.map(&:address)
      extra = theirs - ours
      assert_equal coalesced.sort, extra.map(&:first).sort, "weak binds of #{path}"
      assert_equal theirs - extra, ours.sort, "fixups of #{path}"
    end
  end

  def test_the_exports_are_the_defined_symbols
    bundles.each do |path|
      image = Image.read(File.binread(path))
      assert_equal image.defined, image.exports.map(&:name), "exports of #{path}"
    end
  end

  def test_a_non_arm64_image_is_refused
    assert_raises(ArgumentError) { Image.read("\xCF\xFA\xED\xFE".b + ("\0".b * 28)) }
    assert_raises(ArgumentError) { Image.read([Image::FAT_MAGIC, 0].pack("N2")) }
  end

  private

  # `dyld_info -fixups`'s rows as `[address, type, target]`.
  def dyld_fixups(path)
    tool("dyld_info", "-fixups", path).lines.filter_map do |line|
      fields = line.split
      next unless fields.size >= 5 && fields[2].start_with?("0x")

      [Integer(fields[2]), fields[3], fields[4..].join(" ")]
    end.sort
  end

  # How dyld_info names a bind's target: its library's short name, then
  # the symbol, then a weak import's mark. The short name drops `.dylib`
  # and then the last dotted part: libSystem.B.dylib is libSystem, and
  # libruby.4.1.dylib is libruby.4.
  def bind_target(image, bind)
    library = case bind.library
              when Image::SELF then "<this-image>"
              when Image::MAIN_EXECUTABLE then "<main-executable>"
              when Image::FLAT_LOOKUP then "<flat-namespace>"
              when Image::WEAK_LOOKUP then "<weak-def-coalesce>"
              else File.basename(image.dylibs.fetch(bind.library - 1)).delete_suffix(".dylib").sub(/\.[^.]*\z/, "")
              end
    target = "#{library}/#{bind.name}"
    target += format(" + 0x%X", bind.addend) unless bind.addend.zero?
    target += " [weak-import]" if bind.weak
    target
  end
end
