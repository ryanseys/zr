# frozen_string_literal: true
# zr-test: on elf

require "test_helper"
require_relative "../support/obj_unit"
require_relative "../../lib/zr/native/build"
require_relative "../../test/native/fixtures"

# Tests the ELF writer by reading its output back in Ruby. The object must
# contain what a link on an aarch64-linux host needs. On that host, each
# native fixture also links statically and runs.
class ElfTest < Minitest::Test
  Obj = Zr::Obj
  Elf = Zr::Obj::Elf::ObjectFile

  MAIN_EXIT_3 = Zr::Test::ObjUnit::MAIN_EXIT_3

  Section = Struct.new(:name, :type, :flags, :offset, :size, :link, :info, :align, :entsize)
  Sym = Struct.new(:name, :bind, :type, :shndx, :size)

  def unit = Zr::Test::ObjUnit.unit(addend: 4)

  # Returns `[sections, symbols, relocations by section name]` of an
  # object's bytes.
  def read(bytes)
    assert_equal "\x7FELF".b, bytes[0, 4]
    assert_equal [2, 1, 1], bytes[4, 3].unpack("C3"), "64-bit, little-endian, version 1"
    type, machine = bytes[16, 4].unpack("S<S<")
    assert_equal [Elf::ET_REL, Elf::EM_AARCH64], [type, machine]
    shoff = bytes[40, 8].unpack1("Q<")
    shnum, shstrndx = bytes[60, 4].unpack("S<S<")
    first = bytes[shoff, 64].unpack("L<L<Q<Q<Q<Q<L<L<Q<Q<")
    shnum = first[5] if shnum.zero?
    shstrndx = first[6] if shstrndx == Elf::SHN_XINDEX
    raw = (0...shnum).map { |i| bytes[shoff + (i * 64), 64].unpack("L<L<Q<Q<Q<Q<L<L<Q<Q<") }
    strings = ->(section, at) { bytes[(section[4] + at)..].unpack1("Z*") }
    names = raw[shstrndx]
    sections = raw.map { |r| Section.new(strings.call(names, r[0]), r[1], r[2], r[4], r[5], r[6], r[7], r[8], r[9]) }
    symtab = sections.find { |s| s.type == Elf::SHT_SYMTAB }
    strtab = raw[symtab.link]
    wide = sections.find { |s| s.type == Elf::SHT_SYMTAB_SHNDX }
    symbols = (0...(symtab.size / 24)).map do |i|
      name, info, _other, shndx, _value, size = bytes[symtab.offset + (i * 24), 24].unpack("L<CCS<Q<Q<")
      shndx = bytes[wide.offset + (i * 4), 4].unpack1("L<") if shndx == Elf::SHN_XINDEX
      Sym.new(strings.call(strtab, name), info >> 4, info & 0xF, shndx, size)
    end
    relocs = sections.select { |s| s.type == Elf::SHT_RELA }.to_h do |s|
      rows = (0...(s.size / 24)).map do |i|
        offset, rinfo, addend = bytes[s.offset + (i * 24), 24].unpack("Q<Q<q<")
        [offset, rinfo & 0xFFFFFFFF, symbols[rinfo >> 32].name, addend]
      end
      [sections[s.info].name, rows]
    end
    [sections, symbols, relocs, symtab]
  end

  def test_every_item_is_a_section_of_its_own
    sections, = read(Elf.write(unit, arch: :aarch64))
    by_name = sections.to_h { |s| [s.name, s] }
    assert_equal Elf::SHF_ALLOC | Elf::SHF_EXECINSTR, by_name.fetch(".text.main").flags
    assert_equal Elf::SHF_ALLOC, by_name.fetch(".rodata.msg").flags
    assert_equal Elf::SHF_ALLOC | Elf::SHF_WRITE, by_name.fetch(".data.rel.ro.table").flags
    assert_equal Elf::SHT_NOBITS, by_name.fetch(".bss.counter").type
    assert_equal 16, by_name.fetch(".bss.counter").size
    assert by_name.key?(".note.GNU-stack"), "the stack is not executable"
  end

  # An import with a pinned version names it, as `.symver` does, so ld
  # binds that version; a name that the unit defines keeps its name.
  def test_a_pinned_import_names_its_version
    _, symbols, relocs = read(Elf.write(unit, arch: :aarch64, versions: { "exit" => "GLIBC_2.17", "main" => "GLIBC_2.17" }))

    assert_equal %w[exit@GLIBC_2.17 main msg], symbols.reject { |s| s.bind == Elf::STB_LOCAL }.map(&:name)
    assert_equal "exit@GLIBC_2.17", relocs.fetch(".text.main").first[2]
  end

  # Every object that a glibc build writes, the runtime's too, names the
  # pinned versions; a musl one, which links libc statically, names none.
  def test_a_glibc_object_names_the_pinned_versions_and_a_musl_one_none
    u = Obj::Unit.new.function("main", MAIN_EXIT_3, relocs: [Obj::Reloc.new(4, :branch26, "fmod")])
    names = lambda do |target|
      _, symbols, = read(Zr::Native::Build.object_bytes(u, target))
      symbols.map(&:name).grep(/fmod/)
    end

    assert_equal ["fmod@GLIBC_2.17"], names.call(Zr::Target::AARCH64_LINUX_GNU)
    assert_equal ["fmod"], names.call(Zr::Target::AARCH64_LINUX_MUSL)
  end

  def test_the_symbols_are_locals_first_with_no_prefix
    _, symbols, _, symtab = read(Elf.write(unit, arch: :aarch64))
    assert_equal "", symbols.first.name
    locals = symbols.take_while { |s| s.bind == Elf::STB_LOCAL }
    assert_equal symtab.info, locals.size, "sh_info is the first global"
    assert_equal ["", "counter", "table"], locals.map(&:name)
    globals = symbols.drop(locals.size)
    assert_equal %w[exit main msg], globals.map(&:name)
    assert_equal Elf::SHN_UNDEF, globals.find { |s| s.name == "exit" }.shndx
    assert_equal Elf::STT_FUNC, globals.find { |s| s.name == "main" }.type
    assert_equal 11, globals.find { |s| s.name == "msg" }.size
  end

  def test_relocations_include_type_symbol_and_addend
    _, _, relocs = read(Elf.write(unit, arch: :aarch64))
    assert_equal [[4, Elf::RELOC.fetch(:branch26), "exit", 0]], relocs.fetch(".text.main")
    assert_equal [[0, Elf::RELOC.fetch(:abs64), "msg", 4]], relocs.fetch(".data.rel.ro.table")
  end

  def test_every_native_fixture_writes_an_object_that_reads_back
    Zr::Native::Fixtures::NAMES.each do |name|
      functions, data = Zr::Native::Fixtures.build(name)
      Dir.mktmpdir("zr-elf-") do |dir|
        obj = File.join(dir, "#{name}.o")
        assert_nil Zr::Native::Build.object(functions, data, obj, target: Zr::Target::AARCH64_LINUX_MUSL)
        sections, symbols, relocs = read(File.binread(obj))
        assert symbols.any? { |s| s.name == "main" && s.type == Elf::STT_FUNC }, name
        relocs.each_value { |rows| rows.each { |_, type, _, _| assert_includes Elf::RELOC.values, type, name } }
        assert sections.any? { |s| s.name == ".text.main" }, name
      end
    end
  end

  # With SHN_LORESERVE or more sections, the header fields are too small
  # for the count. Section 0 and `.symtab_shndx` then contain the real
  # indices.
  def test_section_count_past_header_limit_uses_extended_indices
    u = Obj::Unit.new
    count = Elf::SHN_LORESERVE + 16
    count.times { |i| u.datum("d#{i}", :data, "\0" * 8, linkage: :export) }
    u.function("main", MAIN_EXIT_3, relocs: [Obj::Reloc.new(4, :branch26, "d#{count - 1}")])
    sections, symbols, relocs = read(Elf.write(u, arch: :aarch64))
    last = symbols.find { |s| s.name == "d#{count - 1}" }
    assert_equal ".data.d#{count - 1}", sections[last.shndx].name
    assert_equal "d#{count - 1}", relocs.fetch(".text.main").first[2]
  end

  def test_llvm_readelf_reads_the_object
    readelf = ["llvm-readelf", "readelf", "/opt/homebrew/opt/llvm/bin/llvm-readelf"].find { |tool| system("command -v #{tool} > /dev/null 2>&1") }
    skip "no readelf" unless readelf
    Dir.mktmpdir("zr-elf-") do |dir|
      obj = File.join(dir, "u.o")
      File.binwrite(obj, Elf.write(unit, arch: :aarch64))
      out = IO.popen([readelf, "-r", "-s", obj], err: %i[child out], &:read)
      assert_predicate $?, :success?, out
      assert_match(/R_AARCH64_CALL26\s+0+\s+exit/, out)
      assert_match(/R_AARCH64_ABS64\s+0+\s+msg \+ 4/, out)
    end
  end

  # A cross toolchain can link here, but only a host of the target can
  # run the binary. On other hosts, the test reads the binary's header.
  def test_a_native_fixture_links_statically_and_runs
    fixtures_run(Zr::Target::AARCH64_LINUX_MUSL, 183)
  end

  def test_a_native_fixture_links_statically_and_runs_on_x86_64
    fixtures_run(Zr::Target::X86_64_LINUX_MUSL, 62)
  end

  def fixtures_run(target, machine)
    skip "a static link needs a #{target} host or toolchain" unless target.linkable?
    Zr::Native::Fixtures::NAMES.each do |name|
      functions, data = Zr::Native::Fixtures.build(name)
      Dir.mktmpdir("zr-elf-") do |dir|
        bin = File.join(dir, name)
        assert_nil Zr::Native::Build.binary(functions, data, bin, work: dir, target: target)
        assert_static_executable File.binread(bin), machine, name
        next unless target.native?

        out = IO.popen([bin], &:read)
        assert_equal 0, $?.exitstatus, "#{name} exited #{$?.exitstatus}"
        assert_equal File.binread(File.join(ROOT, "test/native/#{name}.out")), out
      end
    end
  end

  # Checks for ET_EXEC for `machine`, with no PT_INTERP, so no loader
  # runs first.
  def assert_static_executable(bytes, machine, name)
    assert_equal "\x7FELF".b, bytes.byteslice(0, 4), name
    type, kind = bytes.byteslice(16, 4).unpack("S<S<")
    assert_equal [2, machine], [type, kind], name
    phoff = bytes.byteslice(32, 8).unpack1("Q<")
    phentsize, phnum = bytes.byteslice(54, 4).unpack("S<S<")
    kinds = Array.new(phnum) { |i| bytes.byteslice(phoff + (i * phentsize), 4).unpack1("L<") }
    refute_includes kinds, 3, "#{name} names a program interpreter"
  end
end
