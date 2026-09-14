# frozen_string_literal: true

require_relative "helper"
require "fiddle"
require_relative "../../lib/ze0/obj/macho/executable"

# The libSystem names `Obj::MachO::Executable` links against. The list is committed
# so that a build answers the same on every host; a stale one refuses a
# link `Obj::MachO::Executable` could make, so the check writes it again and demands
# the same bytes. `ZE0_BLESS=1` rewrites it.
class LibsystemTest < Minitest::Test
  PATH = File.join(ROOT, "lib/ze0/obj/macho/libsystem.rb")

  def test_the_list_matches_the_imports
    text = IO.popen([RbConfig.ruby, "-I#{File.join(ROOT, "lib")}", File.join(ROOT, "tools/libsystem.rb")], &:read)
    assert $?.success?, "tools/libsystem.rb failed"

    if ENV["ZE0_BLESS"] == "1"
      File.write(PATH, text)
      skip "blessed #{PATH}"
    end
    assert_equal File.read(PATH), text, "#{PATH} is stale (ZE0_BLESS=1 to accept)"
  end

  def test_every_listed_name_is_in_this_hosts_libsystem
    libsystem = Fiddle::Handle.new(Ze0::Obj::MachO::Executable::LIBSYSTEM)
    Ze0::Obj::MachO::Executable::LIBSYSTEM_NAMES.each { |name| assert libsystem[name], name }
  end

  def test_a_name_off_the_list_is_not_libsystems
    refute Ze0::Obj::MachO::Executable.libsystem?("onig_new")
    assert Ze0::Obj::MachO::Executable.libsystem?("write")
  end
end
