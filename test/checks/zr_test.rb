# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/machine/lower"
require_relative "../../lib/ze0/native/build"

# The kernel dialect: each `test/zr/<name>.rb` compiles to a binary on
# both native roads and prints `<name>.stdout`; each `test/zr/refused/`
# fixture draws the refusal its first line names.
class ZrTest < Minitest::Test
  ROADS = { ruby: Ze0::Native::Build.road("ruby", ROOT), cranelift: Ze0::Native::Build.road("cranelift", ROOT) }.freeze

  Dir[File.join(ROOT, "test/zr/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    ROADS.each do |label, road|
      define_method("test_#{label}_#{name}") do
        skip "clif2obj is not built (bin/ze0 native build)" unless road.available?

        functions, data = Ze0::Machine.compile(File.read(rb), rb)
        Dir.mktmpdir("ze0-zr-") do |dir|
          bin = File.join(dir, name)
          assert_nil Ze0::Native::Build.binary(functions, data, bin, road: road, work: dir)
          out = IO.popen([bin], &:read)
          assert_equal 0, $?.exitstatus, "#{name} on the #{label} road exited #{$?.exitstatus}"
          assert_equal File.binread(rb.sub(/\.rb\z/, ".stdout")), out
        end
      end
    end
  end

  Dir[File.join(ROOT, "test/zr/refused/*.rb")].sort.each do |rb|
    define_method("test_refused_#{File.basename(rb, ".rb")}") do
      source = File.read(rb)
      want = source.lines.first.to_s[/\A# (.+)\n/, 1]
      refute_nil want, "#{rb}: no `# <expected refusal>` first line"
      e = assert_raises(Ze0::Machine::Refused, "#{rb}: compiled, but must be refused") { Ze0::Machine.compile(source, rb) }
      assert_includes e.message, want
    end
  end
end
