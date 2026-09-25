# frozen_string_literal: true

require "test_helper"
require "fiddle"
require_relative "../../lib/zr/obj/macho/executable"

# Tests the list of libSystem symbols that `Obj::MachO::Executable` links
# against. The list is in the repository, so that a build gives the same
# result on each host. A stale list refuses a link that the writer can
# make. Thus the test writes the list again and requires the same bytes.
# `ZR_BLESS=1` writes it again.
class LibsystemTest < Minitest::Test
  # Only a darwin host has Mach-O, libSystem and the darwin JIT.
  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
  end

  PATH = File.join(ROOT, "lib/zr/obj/macho/libsystem.rb")

  def test_the_list_matches_the_imports
    out, ok = Checks.generate("libsystem")
    assert ok, "#{out}#{PATH} is stale (ZR_BLESS=1 writes it)"
  end

  def test_every_listed_name_is_in_this_hosts_libsystem
    libsystem = Fiddle::Handle.new(Zr::Obj::MachO::Executable::LIBSYSTEM)
    Zr::Obj::MachO::Executable::LIBSYSTEM_NAMES.each { |name| assert libsystem[name], name }
  end

  def test_a_name_off_the_list_is_not_libsystems
    refute Zr::Obj::MachO::Executable.libsystem?("pm_buffer_init")
    assert Zr::Obj::MachO::Executable.libsystem?("write")
  end
end
