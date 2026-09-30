# frozen_string_literal: true

require "prism"

module Zr
  module Dev
    module Gems
      # A gem's own file, `gems/<name>.rb`, for a gem that the tool cannot
      # guess right:
      #
      #   # zr-gems: skip -- needs a running Redis
      #
      #   require "active_support"
      #   require "active_support/core_ext"
      #
      # A line `# zr-gems: skip -- <reason>` skips the gem. The literal
      # top-level requires name the features that the probe requires, in
      # place of the guess. A file with more than requires is also a smoke
      # program: when it gives ruby's output as a zr binary, the gem is
      # `verified`.
      class Override
        SKIP = /^#\s*zr-gems:\s*skip\s*--\s*(.+)$/

        attr_reader :path, :source

        # The override of `name` in `dir`, or nil.
        def self.for(name, dir: HOME)
          path = File.join(dir, "#{name}.rb")
          File.file?(path) ? new(path) : nil
        end

        def initialize(path)
          @path = path
          @source = File.read(path)
          @statements = Prism.parse(@source).value.statements.body
        end

        # The reason to skip the gem, or nil.
        def skip = @source[SKIP, 1]&.strip

        # The features of the top-level `require "..."` calls.
        def requires = @statements.filter_map { |node| feature(node) }

        # True when the file does more than require.
        def smoke? = @statements.any? { |node| feature(node).nil? }

        private

        def feature(node)
          return nil unless node.is_a?(Prism::CallNode) && node.name == :require && node.receiver.nil?

          args = node.arguments&.arguments
          args&.one? && args.first.is_a?(Prism::StringNode) ? args.first.unescaped : nil
        end
      end
    end
  end
end
