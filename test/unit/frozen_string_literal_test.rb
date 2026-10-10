# frozen_string_literal: true

require "test_helper"

# The runtime's core, ext and lib files freeze their string literals, as
# ruby's own C does. Without the comment, a program built with
# `--enable=frozen-string-literal` would freeze them too, and an ext file
# that appends to a literal would raise where ruby does not. RuboCop
# excludes these directories, so this test checks the comment.
class FrozenStringLiteralTest < Minitest::Test
  RUNTIME = File.join(ROOT, "lib/zr/runtime")

  # The files that keep `false`, with the reason.
  UNFROZEN = {
    "ext/rbconfig.rb" => "mkmf calls `replace` on the CONFIG strings, as on ruby's"
  }.freeze

  def magic(file) = File.foreach(file).first(3).join[/^# frozen_string_literal: (\w+)$/, 1]

  def test_each_core_ext_and_lib_file_freezes_its_literals
    files = Dir.glob("{core,ext,lib}/**/*.rb", base: RUNTIME).sort
    wrong = files.reject { |rel| magic(File.join(RUNTIME, rel)) == (UNFROZEN.key?(rel) ? "false" : "true") }
    assert_empty wrong
  end
end
