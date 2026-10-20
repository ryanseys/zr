# frozen_string_literal: true
# zr-test: on glibc

require "test_helper"
require_relative "../../lib/zr/obj/elf/image"
require_relative "../../lib/zr/cli/commands/inspect"

# The glibc versions that a dynamic binary needs, read from its
# .gnu.version_r. A binary for a glibc target must load on the floor,
# glibc 2.35 (Ubuntu 22.04 and Debian 12).
class GlibcFloorTest < Minitest::Test
  Image = Zr::Obj::Elf::Image
  FLOOR = "2.35"

  # An x86-64 ELF file with no program, whose sections are a null header,
  # .dynstr, .gnu.version_r and .shstrtab. `needs` gives each file's
  # versions.
  def binary(needs)
    dynstr = +"\0"
    at = lambda do |name|
      dynstr.index("#{name}\0") || (dynstr.bytesize.tap { dynstr << name << "\0" })
    end
    entries = needs.map { |file, versions| [at.call(file), versions.map { |v| at.call(v) }] }
    verneed = +"".b
    entries.each_with_index do |(file, names), i|
      size = 16 + (names.size * 16)
      following = i == entries.size - 1 ? 0 : size
      verneed << [1, names.size, file, 16, following].pack("S<S<L<L<L<")
      names.each_with_index do |name, j|
        verneed << [0, 0, j + 2, name, j == names.size - 1 ? 0 : 16].pack("L<S<S<L<L<")
      end
    end
    shstrtab = "\0.dynstr\0.gnu.version_r\0.shstrtab\0".b
    body = dynstr.b + verneed + shstrtab
    shoff = 64 + body.bytesize
    header = "\x7FELF".b + [2, 1, 1].pack("C3") + ("\0" * 9) +
             [2, Image::EM_X86_64, 1, 0, 0, shoff, 0, 64, 0, 0, 64, 4, 3].pack("S<S<L<Q<Q<Q<L<S<S<S<S<S<S<")
    section = ->(name, type, offset, size, link) { [name, type, 0, 0, offset, size, link, 0, 1, 0].pack(Image::SECTION_HEADER) }
    headers = [
      section.call(0, 0, 0, 0, 0),
      section.call(1, Image::SHT_STRTAB, 64, dynstr.bytesize, 0),
      section.call(9, Image::SHT_GNU_VERNEED, 64 + dynstr.bytesize, verneed.bytesize, 1),
      section.call(24, Image::SHT_STRTAB, 64 + dynstr.bytesize + verneed.bytesize, shstrtab.bytesize, 0)
    ]
    header + body + headers.join
  end

  def test_the_needed_versions_are_read_for_each_file
    image = Image.read(binary("libm.so.6" => ["GLIBC_2.2.5", "GLIBC_2.29"], "libc.so.6" => ["GLIBC_2.34", "GLIBC_2.2.5"]))
    expected = { "libm.so.6" => ["GLIBC_2.2.5", "GLIBC_2.29"], "libc.so.6" => ["GLIBC_2.34", "GLIBC_2.2.5"] }
    assert_equal expected, image.needed_versions
  end

  def test_the_glibc_is_the_newest_version_by_number_not_by_text
    image = Image.read(binary("libc.so.6" => ["GLIBC_2.9", "GLIBC_2.34", "GLIBC_PRIVATE", "GLIBC_2.17"]))
    assert_equal "2.34", image.glibc
  end

  def test_a_binary_with_no_version_needs_has_no_glibc
    image = Image.read(binary({}).sub(".gnu.version_r", ".gnu.nothing_r"))
    assert_equal({}, Image.read(binary({})).needed_versions)
    assert_nil image.glibc
  end

  def test_inspect_reads_the_glibc_of_an_elf_binary_and_nil_of_another
    Dir.mktmpdir do |dir|
      elf = File.join(dir, "elf")
      File.binwrite(elf, binary("libc.so.6" => ["GLIBC_2.34"]))
      other = File.join(dir, "other")
      File.binwrite(other, "\xCF\xFA\xED\xFE".b)
      assert_equal "2.34", Zr::CLI::Commands::Inspect.glibc(elf)
      assert_nil Zr::CLI::Commands::Inspect.glibc(other)
    end
  end

  # A binary that this host links for a glibc target needs no glibc newer
  # than the floor. It runs when the target's cc is on the PATH.
  def test_a_glibc_build_needs_no_glibc_above_the_floor
    target = [Zr::Target::AARCH64_LINUX_GNU, Zr::Target::X86_64_LINUX_GNU].find(&:linkable?)
    skip "no C compiler for a glibc target on the PATH" unless target

    Dir.mktmpdir do |dir|
      source = File.join(dir, "hello.rb")
      File.write(source, "puts [3, 1, 2].sort.inspect\n")
      out = File.join(dir, "hello")
      _, err, status = Open3.capture3(File.expand_path("../../bin/zr", __dir__), "build", "--target", target.triple, source, "-o", out)
      assert_predicate status, :success?, err
      glibc = Image.read(File.binread(out)).glibc
      assert glibc, "a dynamic binary needs some glibc version"
      assert_operator Gem::Version.new(glibc), :<=, Gem::Version.new(FLOOR), "needs glibc #{glibc}, above the floor #{FLOOR}"
    end
  end
end
