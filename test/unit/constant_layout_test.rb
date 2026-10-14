# frozen_string_literal: true

require "test_helper"
require "prism"

# Zeitwerk does not load zr, but the layout follows its rule: the path
# `lib/zr/cache/store.rb` names the constant `Zr::Cache::Store`. A reader
# who finds a constant must find its file without a search, and a file
# must hold the constant that its name says.
#
# This parses every compiler file under `lib/zr` with prism. A file
# passes when it defines or reopens the constant that its path names: a
# `module` or `class` statement (nested, or with a `::` path), or a
# constant assignment such as `X = Data.define`. A file that does not
# is in one of two tables, each entry with its reason:
#
# - REOPENS: a topic file that adds one part to a parent constant.
# - EXCEPTIONS: a file that cannot follow the rule.
class ConstantLayoutTest < Minitest::Test
  LIB = Pathname.new(File.join(ROOT, "lib/zr")).freeze

  # The path words that are not plain capitalized words. All other words
  # become a constant name by capitalizing each `_` part.
  INFLECT = {
    "aarch64" => "Aarch64",
    "cli" => "CLI",
    "dce" => "DCE",
    "elf" => "Elf",
    "gvn" => "GVN",
    "ir" => "IR",
    "jit" => "JIT",
    "licm" => "LICM",
    "macho" => "MachO",
    "mem2reg" => "Mem2Reg",
  }.freeze

  # Topic files. The key is the path under `lib/zr`. The value is the
  # constant that the file reopens, and why.
  REOPENS = {
    "backend/aarch64/codegen/layout.rb" => ["Zr::Backend::Aarch64::Codegen", "the frame layout part of the code generator"],
    "backend/aarch64/codegen/moves.rb" => ["Zr::Backend::Aarch64::Codegen", "the register move part of the code generator"],
    "backend/wasm/shims.rb" => ["Zr::Backend::Wasm::Codegen", "the libc shims of the wasm code generator"],
    "eval/interpreter/evaluate.rb" => ["Zr::Eval::Interpreter", "the entry point of the interpreter, Interpreter.evaluate"],
    "hir/build/coverage.rb" => ["Zr::Hir::Build", "the coverage part of Build"],
    "hir/build/literals.rb" => ["Zr::Hir::Build", "the literal part of Build"],
    "hir/build/requires.rb" => ["Zr::Hir::Build", "the require part of Build"],
    "hir/build/usings.rb" => ["Zr::Hir::Build", "the using part of Build"],
    "hir/features.rb" => ["Zr::Hir", "the feature table of the Hir namespace"],
    "hir/preludes.rb" => ["Zr::Hir::Build", "the prelude part of Build"],
    "machine/function/intrinsics.rb" => ["Zr::Machine::Function", "the intrinsic part of Function"],
    "lower/function/sends/arith.rb" => ["Zr::Lower::Function::Sends", "the arithmetic part of Sends"],
    "lower/function/sends/in_place.rb" => ["Zr::Lower::Function::Sends", "the in-place update part of Sends"],
    "lower/function/sends/refinements.rb" => ["Zr::Lower::Function::Sends", "the refinement part of Sends"],
    "obj/macho/libsystem.rb" => ["Zr::Obj::MachO::Executable", "the libSystem table of Executable"],
    "obj/model.rb" => ["Zr::Obj", "the object model: Reloc, Code, Datum and Unit are one unit"],
  }.freeze

  # Files that cannot follow the rule. A nil constant means that the file
  # defines none.
  EXCEPTIONS = {
    "ext/target_rbconfig.rb" => [nil, "a file that mkmf loads into MakeMakefile for --target-rbconfig; it is never required"],
    "gem_set/resolve.rb" => ["ZrGemSet", "a script that a child ruby runs with its own load path; it is never required"],
    "ir.rb" => [nil, "the aggregator of the IR files: it requires them and defines no constant"],
    "parse.rb" => [nil, "sets up the host's prism and defines the method Zr.parse"],
    "prism_shim/prism/prism.rb" => [nil, "stands in for prism's C extension on the load path"],
    "ruby_version.rb" => ["Zr::RUBY_PIN", "the generated record of the pinned ruby: constants of Zr, as version.rb holds"],
    "version.rb" => ["Zr::VERSION", "holds the version constants, as a gemspec expects"],
  }.freeze

  ACCEPTED = REOPENS.merge(EXCEPTIONS).freeze

  # The compiled runtime has its own layout, and a program embeds it.
  RUNTIME = (LIB + "runtime").freeze

  def test_every_file_defines_the_constant_its_path_names
    mismatches = files.filter_map do |file|
      path = relative(file)
      expected = expected_constant(path)
      next if ACCEPTED.key?(path) || defined_names(file).include?(expected)

      "lib/zr/#{path}: expected #{expected}"
    end

    assert_empty mismatches, "A file must define the constant that its path names. " \
                             "Rename the file, or add it to REOPENS or EXCEPTIONS with a reason."
  end

  def test_every_listed_file_exists
    missing = ACCEPTED.keys.reject { |path| (LIB + path).exist? }

    assert_empty missing
  end

  def test_no_file_is_in_two_tables
    keys = [REOPENS, EXCEPTIONS].flat_map(&:keys)

    assert_equal keys.uniq, keys
  end

  def test_every_listed_file_defines_the_constant_that_its_entry_names
    wrong = ACCEPTED.filter_map do |path, (constant, _reason)|
      path if constant && !defined_names(LIB + path).include?(constant)
    end

    assert_empty wrong, "These files do not define the constant that their entry names."
  end

  def test_no_listed_file_defines_the_constant_its_path_names
    needless = ACCEPTED.keys.select { |path| defined_names(LIB + path).include?(expected_constant(path)) }

    assert_empty needless, "These files follow the rule now: remove them from their table."
  end

  private

  def files = LIB.glob("**/*.rb").reject { |path| path.to_s.start_with?("#{RUNTIME}/") }.sort

  def relative(file) = file.relative_path_from(LIB).to_s

  # `cache/store.rb` -> "Zr::Cache::Store"
  def expected_constant(path)
    names = path.delete_suffix(".rb").split("/").map do |word|
      INFLECT.fetch(word) { word.split("_").map(&:capitalize).join }
    end
    ["Zr", *names].join("::")
  end

  # The full name of every module, class and constant that a file
  # defines.
  def defined_names(file)
    names = []
    walk(Prism.parse_file(file.to_s).value, [], names)
    names
  end

  def walk(node, nesting, names)
    case node
    when Prism::ModuleNode, Prism::ClassNode
      full = nesting + path_of(node.constant_path)
      names << full.join("::")
      walk(node.body, full, names) if node.body
    when Prism::ConstantWriteNode
      names << (nesting + [node.name.to_s]).join("::")
      walk(node.value, nesting, names)
    when Prism::ConstantPathWriteNode
      names << (nesting + path_of(node.target)).join("::")
      walk(node.value, nesting, names)
    else
      node.compact_child_nodes.each { |child| walk(child, nesting, names) }
    end
  end

  # The parts of `A::B::C`. A path with a dynamic part gives no parts.
  def path_of(node)
    case node
    when Prism::ConstantReadNode then [node.name.to_s]
    when Prism::ConstantPathNode then (node.parent ? path_of(node.parent) : []) + [node.name.to_s]
    else []
    end
  end
end
