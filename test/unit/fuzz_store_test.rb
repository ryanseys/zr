# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../tool/lib/zr/dev/fuzz"

# Tests what `zr-dev fuzz` keeps below log/fuzz: buckets, cases, issue
# lines, coverage and the corpus (tool/lib/zr/dev/fuzz/store.rb), and
# which seed files it takes (corpus.rb).
class FuzzStoreTest < Minitest::Test
  Fuzz = Zr::Dev::Fuzz

  def result(out_ruby, out_zr)
    verdict = Fuzz::Classify.verdict(Zr::Harness::Answer.new(out_ruby.b, "".b, 0, nil), nil,
                                     Zr::Harness::Answer.new(out_zr.b, "".b, 0, nil))
    Fuzz::Oracle::Result.new(verdict: verdict, ruby: Zr::Harness::Answer.new(out_ruby.b, "".b, 0, nil),
                             zr: Zr::Harness::Answer.new(out_zr.b, "".b, 0, nil))
  end

  def test_count_tells_a_new_bucket_once
    Dir.mktmpdir do |dir|
      store = Fuzz::Store.new(root: dir, run: "r")
      res = result("1\n", "2\n")

      assert store.count("b1", res.verdict, first: "f1")
      refute store.count("b1", res.verdict, first: "f2")
      assert_equal 2, store.buckets["b1"]["count"]
      assert_equal "b1", store.bucket_of("f2")
      assert_nil store.bucket_of("f3")
    end
  end

  def test_add_case_writes_the_case_its_expected_output_and_an_issue_line
    Dir.mktmpdir do |dir|
      store = Fuzz::Store.new(root: dir, run: "r")
      res = result("1\n", "2\n")
      store.count("b1", res.verdict)
      rel = store.add_case("b1", "r-1", res, source: "p 1\n", original: "x = 1\np x\n", meta: { origin: "gen" })
      base = File.join(dir, "cases", "b1", "r-1")

      assert_equal "p 1\n", File.read("#{base}.rb")
      assert_equal "x = 1\np x\n", File.read("#{base}.orig.rb")
      assert_equal "1\n", File.read("#{base}.rb.expected")
      assert_includes File.read("#{base}.diff"), "+2"
      line = JSON.parse(File.readlines(store.issues_path).last)
      assert_equal %w[b1 gen r-1], [line["bucket"], line["origin"], line["id"]]
      assert_equal rel, store.buckets["b1"]["smallest"]["path"]
    end
  end

  def test_a_new_store_reads_the_buckets_and_the_coverage_back
    Dir.mktmpdir do |dir|
      store = Fuzz::Store.new(root: dir, run: "r")
      store.count("b1", result("1\n", "2\n").verdict)

      assert_equal %w[a:1 b:2], store.cover(%w[a:1 b:2])
      assert_equal %w[c:3], store.cover(%w[a:1 c:3])
      store.save_coverage
      again = Fuzz::Store.new(root: dir, run: "s")

      assert_equal %w[b1], again.buckets.keys
      assert_equal 3, again.coverage.size
    end
  end

  def test_finish_writes_the_done_line_and_a_summary_row
    Dir.mktmpdir do |dir|
      store = Fuzz::Store.new(root: dir, run: "r")
      store.finish({ programs: 4, valid: 3 })

      assert JSON.parse(File.readlines(store.issues_path).last)["done"]
      assert_match(/\Ar\t4\t3\t/, File.readlines(File.join(dir, "runs", "summary.tsv")).last)
    end
  end

  def test_corpus_skips_programs_with_sidecars_that_need_more_than_a_run
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.rb"), "p 1\n")
      File.write(File.join(dir, "b.rb"), "p ARGV\n")
      File.write(File.join(dir, "b.rb.args"), "x\n")
      File.write(File.join(dir, "c.txt"), "1 + 1\n")
      File.write(File.join(dir, "c.orig.rb"), "p 2\n")

      assert_equal %w[a.rb c.txt], Fuzz::Corpus.files([dir]).map { File.basename(_1) }
    end
  end
end
