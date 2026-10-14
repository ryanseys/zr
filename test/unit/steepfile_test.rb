# frozen_string_literal: true

require "test_helper"
require "prism"
require "steep"

# The Steepfile checks every file of the compiler, so a new file cannot
# escape the type check: each file of lib/ is in a level, as inline RBS,
# or as plain Ruby when its types are all in sig/zr (RBS_TYPED). The
# runtime is not checked, except the files that ruby loads too.
class SteepfileTest < Minitest::Test
  STEEPFILE = File.join(ROOT, "Steepfile")

  def setup
    project = Steep::Project.new(steepfile_path: Pathname(STEEPFILE))
    Steep::Project::DSL.parse(project, File.read(STEEPFILE), filename: STEEPFILE)
    @target = project.targets.fetch(0)
  end

  def test_every_compiler_file_is_checked
    unchecked = compiler_files.reject { |file| level(file) }

    assert_empty unchecked, "the Steepfile checks no level of these files"
  end

  def test_a_file_checked_as_plain_ruby_has_its_types_in_sig
    plain = compiler_files.select { |file| @target.possible_source_file?(Pathname(file)) }
    untyped = plain.reject { |file| File.file?(File.join(ROOT, file.sub(%r{\Alib/}, "sig/").sub(/\.rb\z/, ".rbs"))) }

    refute_empty plain
    assert_empty untyped, "these files are not inline, and sig/ has no types for them"
  end

  def test_the_runtime_is_checked_only_where_ruby_loads_it
    loaded = Dir.glob("lib/zr/runtime/**/*.rb", base: ROOT).select { |file| level(file) }

    assert_equal %w[lib/zr/runtime/lib/zr/eval/runtime.rb lib/zr/runtime/lib/zr/eval/world.rb lib/zr/runtime/lib/zr/obj/jit/runtime.rb],
                 loaded.sort
  end

  # Inline RBS types the defs of a `module_function` module as instance
  # methods only; sig/zr/module_function.rbs gives the module functions
  # their types (`extend` of the module itself), and must name each one.
  def test_each_module_function_module_extends_itself_in_sig
    sig = File.read(File.join(ROOT, "sig/zr/module_function.rbs"))
    listed = sig.scan(/^module (\S+)\n  extend \1$/).flatten

    assert_equal module_function_modules.sort, listed.sort
  end

  private

  # The modules of the checked files whose body calls a bare
  # `module_function`.
  def module_function_modules
    checked = compiler_files.select { |file| level(file) }
    checked.flat_map do |file|
      found = []
      walk = lambda do |node, path|
        case node
        when Prism::ModuleNode, Prism::ClassNode
          name = path + [node.constant_path.slice]
          statements = node.body.is_a?(Prism::StatementsNode) ? node.body.body : []
          found << name.join("::") if statements.any? { |s| s.is_a?(Prism::CallNode) && s.name == :module_function && !s.receiver && !s.arguments }
          node.body&.compact_child_nodes&.each { |child| walk.call(child, name) }
        else
          node.compact_child_nodes.each { |child| walk.call(child, path) }
        end
      end
      walk.call(Prism.parse_file(File.join(ROOT, file)).value, [])
      found
    end
  end

  def compiler_files = Dir.glob("lib/**/*.rb", base: ROOT).reject { |file| file.start_with?("lib/zr/runtime/") }

  def level(file)
    path = Pathname(file)
    (@target.possible_inline_source_file?(path) || @target.possible_source_file?(path))&.name
  end
end
