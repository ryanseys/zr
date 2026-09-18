# frozen_string_literal: true

require_relative "deeper"

mark = "shared"
["!"].each { |s| mark += s }

module Spliced
  MARK = "!"

  class Helper
    def self.help = "helped#{Deeper::EXTRA}#{MARK}"
    def self.boom = raise(ArgumentError, "from the spliced file")
  end
end

SHARED_MARK = mark
