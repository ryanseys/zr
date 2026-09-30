# frozen_string_literal: true

require "test_helper"
require_relative "../support/spec"
require_relative "../support/reader"

# `Zr::Reader` is a second implementation of the spec DSL. The real one
# (`Zr::Spec::DSL`) compiles and runs. The reader records and runs
# nothing, so `zr-dev oracle` can check every example against ruby
# without a build.
#
# Two implementations of one DSL can become different, and then nothing
# fails: `zr-dev oracle` continues to pass, because it checks the reader's
# model of the suite, not the suite. These tests keep the two the same.
class ReaderConformanceTest < Minitest::Test
  # A keyword that the reader accepts and the DSL does not is the dangerous
  # case: the reader records a misspelled keyword, and `zr-dev oracle`
  # passes a spec that no run can compile.
  def test_zr_keywords_match_in_dsl_and_reader
    assert_equal keywords(Zr::Spec::DSL, :zr), keywords(Zr::Reader::Sandbox, :zr)
  end

  def test_must_answer_keywords_match_in_dsl_and_reader
    assert_equal keywords(Zr::Spec::Expectation, :must_answer),
                 keywords(Zr::Reader::Sandbox::Recorder, :must_answer)
  end

  # The same names are not enough: an example that omits `stderr:` means
  # stderr **is** empty, and the DSL and the reader must agree on that.
  def test_must_answer_defaults_match_in_dsl_and_reader
    assert_equal defaults(Zr::Spec::Expectation, :must_answer),
                 defaults(Zr::Reader::Sandbox::Recorder, :must_answer)
  end

  # `Zr::Spec::DSL#default_path` delegates to `Reader.path_for`. If the run
  # and `zr-dev oracle` gave a program different paths, they would check
  # different programs.
  def test_a_program_is_named_for_the_file_its_example_lives_in
    assert_equal "core/fiber/fiber_test.rb", Zr::Reader.path_for("test/spec/core/fiber/fiber_test.rb")
    assert_equal "core/fiber/fiber_test.rb",
                 Zr::Reader.path_for(File.join(Zr::Reader::ROOT, "test/spec/core/fiber/fiber_test.rb"))
  end

  # A program gets its name from its file, not from its example, so an
  # example description can be a full sentence. A change to the sentence
  # must not change the path of the program.
  def test_renaming_an_example_cannot_move_its_program
    one = Zr::Reader.path_for("test/spec/core/hash/hash_test.rb")

    assert_equal one, Zr::Reader.path_for("test/spec/core/hash/hash_test.rb")
    assert_equal "core/hash/hash_test.rb", one
  end

  # The reader subtracts its `DEFAULTS` so that `given` contains only what
  # a spec file wrote. If a default is different from the DSL's, an
  # explicit keyword disappears from `given`.
  def test_the_readers_defaults_are_the_dsls_defaults
    assert_equal defaults(Zr::Spec::DSL, :zr), Zr::Reader::Sandbox::DEFAULTS
  end

  # A spec reads a fixture through `fixture(...)`, and the DSL and the
  # reader must give it the same bytes. The run writes them next to the
  # program, and `zr-dev oracle` writes them next to its copy.
  def test_dsl_and_reader_read_a_fixture_the_same_way
    assert_includes Zr::Spec::DSL.ancestors, Zr::Fixtures
    assert_includes Zr::Reader::Sandbox.ancestors, Zr::Fixtures
    assert_equal File.binread("#{Zr::Fixtures::ROOT}/raising_feature/r1.rb"),
                 Zr::Fixtures.fixture("raising_feature/r1.rb")
  end

  # `fixtures(...)` returns the full `files:` hash for fixtures that a
  # program reaches through `../../fixtures/`, so each name is written once.
  def test_fixtures_keys_each_name_the_way_a_program_reaches_it
    got = Zr::Fixtures.fixtures("raising_feature/r1.rb", "raising_feature/r2.rb")

    assert_equal ["../../fixtures/raising_feature/r1.rb", "../../fixtures/raising_feature/r2.rb"], got.keys
    assert_equal Zr::Fixtures.fixture("raising_feature/r1.rb"), got.values.first
  end

  def test_a_missing_fixture_says_so_rather_than_reading_nothing
    e = assert_raises(ArgumentError) { Zr::Fixtures.fixture("no/such/thing.rb") }
    assert_match(/no fixture at test\/fixtures/, e.message)
  end

  private

  def keywords(mod, name)
    mod.instance_method(name).parameters.filter_map { |kind, name| name if kind == :key }.sort
  end

  # The value of each optional keyword when a caller omits it, read from
  # the signature. `parameters` gives the name of a keyword but not its
  # value, and this test needs the value.
  def defaults(mod, name)
    method = mod.instance_method(name)
    file, line = method.source_location
    signature = File.readlines(file)[line - 1]
    keywords(mod, name).to_h { |key| [key, eval(signature[/\b#{key}: *([^,)]+)/, 1])] }
  end
end
