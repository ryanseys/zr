# frozen_string_literal: true

require "test_helper"
require "prism"

# An extension whose C calls rb_define_module raises TypeError when the
# constant holds something other than a module, before its module opens.
# Each port does the same with `Object.send(:native_module, :Name)` as its
# first statement after its requires (lib/zr/runtime/core/module.rb).
class NativeModulesTest < Minitest::Test
  EXT = File.join(ROOT, "lib/zr/runtime/ext")

  # Each port's entry file, and the module that its C defines.
  GUARDED = {
    "coverage.so.rb" => :Coverage, "digest.so.rb" => :Digest, "etc.rb" => :Etc, "fiddle.so.rb" => :Fiddle,
    "json/ext/generator.rb" => :JSON, "json/ext/parser.rb" => :JSON, "nkf.so.rb" => :NKF, "openssl.so.rb" => :OpenSSL,
    "os/darwin/fcntl.rb" => :Fcntl, "os/linux/fcntl.rb" => :Fcntl, "os/wasi/fcntl.rb" => :Fcntl, "psych.so.rb" => :Psych,
    "pty.rb" => :PTY, "syslog_ext.rb" => :Syslog, "zlib.rb" => :Zlib
  }.freeze

  GUARDED.each do |file, name|
    define_method(:"test_#{file.tr("/.", "__")}_checks_#{name}_before_it_opens") do
      statements = Prism.parse_file(File.join(EXT, file)).value.statements.body
      first = statements.find { |node| !(node.is_a?(Prism::CallNode) && node.name == :require) }

      assert_equal "Object.send(:native_module, :#{name})", first.slice, file
    end
  end
end
