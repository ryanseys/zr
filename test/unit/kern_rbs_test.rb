# frozen_string_literal: true

require "test_helper"
require "rbs"

# sig/zr_kern.rbs gives each kernel def's type as Ruby sees it. `zr-dev
# gen kern_rbs` writes it from the kernel's `sig`s, so it cannot drift
# from them.
class KernRbsTest < Minitest::Test
  PATH = File.join(ROOT, "sig/zr_kern.rbs")

  def test_the_file_is_current
    out, ok = Checks.generate("kern_rbs")

    assert ok, "#{out}#{PATH} is stale (ZR_BLESS=1 writes it)"
  end

  def test_rbs_reads_the_file
    _, _, decls = RBS::Parser.parse_signature(File.read(PATH))
    kern = decls.first.members.first

    assert_equal "Kern", kern.name.name.to_s
    assert_operator kern.members.size, :>, 2000
  end
end
