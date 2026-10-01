# frozen_string_literal: true

require "test_helper"
require "prism"
require_relative "../../lib/zr/ir/inst"
require_relative "../../lib/zr/backend/wasm/codegen"

# Some `case` arms write out the opcodes of an `IR::Inst` list, so that the
# compiled `case` does not build an array on each step. Each arm's comment
# names the list. This reads the arms with prism and checks that each list
# is still there in order, so that the constant and the arm stay one fact.
class CaseListsTest < Minitest::Test
  Inst = Zr::IR::Inst
  LIB = File.expand_path("../../lib/zr", __dir__)

  # The symbols of each `when` arm of a file, for the arms of only symbols.
  def arms(path)
    program = Prism.parse_file(File.join(LIB, path)).value
    found = []
    walk = lambda do |node|
      if node.is_a?(Prism::WhenNode) && node.conditions.all?(Prism::SymbolNode)
        found << node.conditions.map { |symbol| symbol.unescaped.to_sym }
      end
      node.compact_child_nodes.each(&walk)
    end
    walk.call(program)
    found
  end

  # Whether some arm of the file has `list` as an unbroken run.
  def arm_with?(path, list)
    arms(path).any? { |arm| arm.each_cons(list.size).include?(list) }
  end

  def test_wasm_body_writes_out_constants
    # Arrange
    list = Zr::Backend::Wasm::Codegen::Body::CONSTANTS

    # Act
    found = arm_with?("backend/wasm/codegen/body.rb", list)

    # Assert
    assert found, "no arm of wasm/codegen/body.rb lists #{list}"
  end

  def test_wasm_body_writes_out_fbinops
    # Arrange
    list = Inst::FBINOPS

    # Act
    found = arm_with?("backend/wasm/codegen/body.rb", list)

    # Assert
    assert found, "no arm of wasm/codegen/body.rb lists #{list}"
  end

  def test_wasm_body_writes_out_funops
    # Arrange
    list = Inst::FUNOPS

    # Act
    found = arm_with?("backend/wasm/codegen/body.rb", list)

    # Assert
    assert found, "no arm of wasm/codegen/body.rb lists #{list}"
  end

  def test_aarch64_codegen_writes_out_fbinops
    # Arrange
    list = Inst::FBINOPS

    # Act
    found = arm_with?("backend/aarch64/codegen.rb", list)

    # Assert
    assert found, "no arm of aarch64/codegen.rb lists #{list}"
  end

  def test_aarch64_codegen_writes_out_funops
    # Arrange
    list = Inst::FUNOPS

    # Act
    found = arm_with?("backend/aarch64/codegen.rb", list)

    # Assert
    assert found, "no arm of aarch64/codegen.rb lists #{list}"
  end

  def test_interp_writes_out_binops
    # Arrange
    list = Inst::BINOPS

    # Act
    found = arm_with?("ir/interp.rb", list)

    # Assert
    assert found, "no arm of interp.rb lists #{list}"
  end

  def test_interp_writes_out_bitops
    # Arrange
    list = Inst::BITOPS

    # Act
    found = arm_with?("ir/interp.rb", list)

    # Assert
    assert found, "no arm of interp.rb lists #{list}"
  end

  def test_interp_writes_out_fbinops_then_funops
    # Arrange
    list = Inst::FBINOPS + Inst::FUNOPS

    # Act
    found = arm_with?("ir/interp.rb", list)

    # Assert
    assert found, "no arm of interp.rb lists #{list}"
  end

  def test_verify_writes_out_binops_then_pairs
    # Arrange
    list = Inst::BINOPS + Inst::PAIRS

    # Act
    found = arm_with?("ir/verify.rb", list)

    # Assert
    assert found, "no arm of verify.rb lists #{list}"
  end

  def test_verify_writes_out_fbinops
    # Arrange
    list = Inst::FBINOPS

    # Act
    found = arm_with?("ir/verify.rb", list)

    # Assert
    assert found, "no arm of verify.rb lists #{list}"
  end

  def test_verify_writes_out_funops
    # Arrange
    list = Inst::FUNOPS

    # Act
    found = arm_with?("ir/verify.rb", list)

    # Assert
    assert found, "no arm of verify.rb lists #{list}"
  end

  def test_verify_writes_out_bitops
    # Arrange
    list = Inst::BITOPS

    # Act
    found = arm_with?("ir/verify.rb", list)

    # Assert
    assert found, "no arm of verify.rb lists #{list}"
  end

  def test_the_files_have_no_splat_arm_of_these_lists
    # Arrange
    paths = %w[backend/wasm/codegen/body.rb backend/aarch64/codegen.rb ir/interp.rb ir/verify.rb]

    # Act
    splats = paths.select { |path| File.read(File.join(LIB, path)).match?(/^\s*when .*\*(IR::)?(Inst::)?[A-Z]/) }

    # Assert
    assert_empty splats
  end
end
