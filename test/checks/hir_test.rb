# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/hir"

# The HIR of each `test/hir/<name>.rb`, dumped as S-expressions, held
# byte for byte in `<name>.hir`; `ZE0_BLESS=1` rewrites.
class HirTest < Minitest::Test
  Dir[File.join(ROOT, "test/hir/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_#{name}") do
      got = Ze0::Hir::Dump.program(Ze0::Hir.build(File.read(rb), "#{name}.rb"))
      want = rb.sub(/\.rb\z/, ".hir")
      if ENV["ZE0_BLESS"]
        File.write(want, got)
      else
        assert File.file?(want), "#{want} is missing (ZE0_BLESS=1 records it)"
        assert_equal File.read(want), got
      end
    end
  end
end
