# frozen_string_literal: true
# zr-test: runtime

require "test_helper"

# Eval support is the compiler that a program with eval links in, and
# every such program carries each file of it. The files that only a build
# on the host reads stay out: the C extension builder, the readers and
# writers of linked images, the JIT's Fiddle host and the HIR dump.
class EvalSupportFilesTest < Minitest::Test
  LIB = File.join(ROOT, "lib/zr")
  HOST_ONLY = %r{\A#{Regexp.escape(LIB)}/(?:ext\.rb|ext/|obj/image\.rb|obj/elf/image\.rb|obj/string_table\.rb|obj/jit/fiddle\.rb|
                 obj/macho/(?:flatten|relink|image|block|object_file)\.rb|hir/dump\.rb)}x

  def test_eval_support_carries_no_file_that_only_a_host_build_reads
    loader = Zr::Hir::Build.eval_support(Zr::Target.default)
    files = loader.units.map(&:file).uniq

    assert_empty files.grep(HOST_ONLY)
    assert_empty files.grep(%r{/(?:digest/sha1|open3)\.rb\z})
  end
end
