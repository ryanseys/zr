# frozen_string_literal: true

require_relative "helper"

# ze0's contract, asked of every form outside its subset: refused BY NAME
# at its line, never compiled to something that answers differently.
#
# Each fixture in `test/refused/` is one such form, and its first line names
# the refusal it must draw. A fixture that starts compiling is the signal
# to delete it: the form is in the subset now.
class RefusedTest < Minitest::Test
  Dir[File.join(ROOT, "test/refused/*.rb")].sort.each do |path|
    define_method("test_#{File.basename(path, ".rb")}") do
      source = File.read(path)
      want = source.lines.first.to_s[/\A# (.+)\n/, 1]
      refute_nil want, "#{path}: no `# <expected refusal>` first line"
      e = assert_raises(Ze0::Unsupported, "#{path}: compiled, but must be refused (#{want.inspect})") do
        Dir.chdir(File.dirname(path)) { Ze0.compile(source, File.basename(path)) }
      end
      assert_includes e.message, want, path
    end
  end
end
