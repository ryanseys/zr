# frozen_string_literal: true

# error_highlight's node lookup, for a program compiled ahead of time.
# CRuby parses the file again with prism when it reports an error, and
# finds the node for a backtrace entry by its id. A program here includes
# no parser. While the compiler had the tree, it called error_highlight's
# own Spotter for each node that an entry can refer to
# (lib/zr/hir/spots.rb), and the program keeps those results. The rest of
# the library runs as ruby ships it.
module ErrorHighlight
  # A node the compiler spotted: its rows, and the file it is in.
  class CompiledNode
    # The node `location` names, or nil where the compiler spotted none.
    def self.find(location)
      path = location.absolute_path or return nil
      id = RubyVM::AbstractSyntaxTree.node_id_for_backtrace_location(location)
      rows = table.dig(location.path, id) or return nil

      new(path, rows)
    end

    # `{ file => { node id => [[point, name, line, column, last line,
    # last column], ...] } }`, read from the program once.
    def self.table
      @table ||= Primitive.zr_load_names(4).split("\f").to_h do |text|
        file, *lines = text.split("\n")
        rows = lines.map(&:split).group_by { |id, *| id.to_i }.transform_values do |group|
          group.map { |_, point, name, *numbers| [point == "n" ? :name : :args, name == "-" ? nil : name.to_sym, *numbers.map(&:to_i)] }
        end
        [file, rows]
      end
    end

    def initialize(path, rows)
      @path = path
      @rows = rows
    end

    # What Spotter#spot returns for the node: the entry for the constant
    # `name`, else the entry that applies to any name.
    def spot(point_type, name)
      row = @rows.find { |point, row_name| point == point_type && row_name == name } ||
            @rows.find { |point, row_name| point == point_type && row_name.nil? }
      return nil unless row

      _, _, first_lineno, first_column, last_lineno, last_column = row
      script_lines = File.read(@path).lines
      snippet = script_lines[first_lineno - 1..last_lineno - 1].join
      snippet += "\n" unless snippet.end_with?("\n")
      { first_lineno:, first_column:, last_lineno:, last_column:, snippet:, script_lines: }
    end
  end
  private_constant :CompiledNode

  def self.prism_find(location) = CompiledNode.find(location)
  private_class_method :prism_find

  # Spotter reads the spot that a compiled node already contains.
  module CompiledSpot
    def spot
      Primitive.attr! :ivars
      @node.is_a?(CompiledNode) ? @node.spot(@point_type, @name) : super
    end
  end
  Spotter.prepend(CompiledSpot)
  private_constant :CompiledSpot
end
