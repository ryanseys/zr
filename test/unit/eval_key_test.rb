# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/runtime"

# The eval support object's key names its code (`Zr.eval_key`), not only
# the files that it was lowered from.
#
# The code contains the id of each name that it uses, the runtime's
# names too. A build with the ledger and a build without it (`rake
# build:self`, `ZR_LEDGER=0`) give the runtime's names other ids, so they
# lower the same files to other code. When the key had only the files,
# the second build wrote its own metadata but linked the first build's
# object (`Native::Build.eval_support_object` keeps an object that has
# its key). Each eval then read a name by the wrong id: `Target#os` was
# nil, and the compiled compiler had no `Target#triple`.
class EvalKeyTest < Minitest::Test
  FILES = "files"
  NAMES = ["zr_intern", "os", "triple", nil, "@os"].freeze

  def key(names, sites = 3) = Zr.eval_key(FILES, names, sites)

  def test_the_same_files_and_table_give_the_same_key
    assert_equal key(NAMES), key(NAMES.dup)
  end

  # A runtime whose table has the same names at other ids, as the ledger
  # gives them.
  def test_a_name_at_another_id_is_another_key
    moved = NAMES.values_at(0, 2, 1, 3, 4)

    refute_equal key(NAMES), key(moved)
  end

  def test_another_site_count_is_another_key
    refute_equal key(NAMES, 3), key(NAMES, 4)
  end

  # Each name has its length, so two names never read as one, and a pad
  # is not an empty name.
  def test_names_cannot_run_together
    refute_equal key(%w[ab c]), key(%w[a bc])
    refute_equal key([nil]), key([""])
  end

  # The eval support that this checkout builds: its object's key is the
  # key of its files and its table, so a build with another table cannot
  # take the object.
  def test_eval_support_is_keyed_by_its_symbol_table
    support = Zr.eval_support(Zr::Target.default)
    meta = support.send(:meta)

    assert_equal Zr.eval_key(meta.fetch("files_key"), meta.fetch("names"), meta.fetch("sites")), support.key
    refute_equal meta.fetch("files_key"), support.key
    assert_equal Zr::EvalSupport.object_path(support.key), support.object_path
  end

  # Eval support stopped on a feature that no root had. A file that later
  # appears there makes it stale, though no file that it read changed
  # (prism/translation/parser was once missing from the vendored prism).
  def test_a_file_where_a_stopped_feature_would_be_changes_the_files_key
    Dir.mktmpdir("zr-eval-key-") do |dir|
      absent = File.join(dir, "prism/translation/parser.rb")
      before = Zr.eval_files_key("digest", [], {}, [absent])
      FileUtils.mkdir_p(File.dirname(absent))
      File.write(absent, "")

      refute_equal before, Zr.eval_files_key("digest", [], {}, [absent])
    end
  end
end
