# frozen_string_literal: true

require "test_helper"
require "prism"
require_relative "../../lib/zr/library/ports"

# Each port says its gem's version where the gem's C does, and that
# version is the one zr owns (Library::Ports::ALL). The test reads the
# constants with Prism: the ports call Primitive, so they load only in a
# binary.
class PortVersionsTest < Minitest::Test
  EXT = File.join(ROOT, "lib/zr/runtime/ext")

  # The ports whose C half gives the version: the files, and the constant.
  CONSTANTS = {
    "bigdecimal" => [%w[bigdecimal.so.rb], :VERSION],
    "debug" => [%w[debug/debug.so.rb], :SO_VERSION],
    "etc" => [%w[etc.so.rb], :VERSION],
    "fcntl" => [%w[os/darwin/fcntl.so.rb os/linux/fcntl.so.rb os/wasi/fcntl.so.rb], :VERSION],
    "io-console" => [%w[io/console.so.rb], :VERSION],
    "nkf" => [%w[nkf.so.rb], :GEM_VERSION],
    "stringio" => [%w[stringio.so.rb], :VERSION],
    "strscan" => [%w[strscan.so.rb], :Version],
    "syslog" => [%w[syslog_ext.so.rb], :VERSION],
    "zlib" => [%w[zlib.so.rb], :VERSION]
  }.freeze

  # The ports whose version is in the gem's Ruby half, which vendor/ or
  # ruby's own library holds at that version.
  RUBY_HALF = %w[date digest ffi fiddle json openssl prism psych racc rbs].freeze

  def test_each_port_is_in_one_list
    assert_equal Zr::Library::Ports::ALL.keys.sort, (CONSTANTS.keys + RUBY_HALF).sort
    assert_empty CONSTANTS.keys & RUBY_HALF
  end

  CONSTANTS.each do |name, (files, constant)|
    define_method(:"test_#{name.tr("-", "_")}_says_its_version") do
      files.each do |file|
        assert_equal Zr::Library::Ports::ALL.fetch(name).version, version(File.join(EXT, file), constant), file
      end
    end
  end

  private

  # The String that `constant` gets in `file`: a literal, or `String.new`
  # of one.
  def version(file, constant)
    write = Prism.parse_file(file).value.breadth_first_search { |node| node.is_a?(Prism::ConstantWriteNode) && node.name == constant }
    value = write.value
    value = value.arguments.arguments.first if value.is_a?(Prism::CallNode)
    value.unescaped
  end
end
