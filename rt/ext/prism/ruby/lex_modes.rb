# frozen_string_literal: true

module Prism
  module Ruby
    # parser_lex's string, list, regexp and heredoc modes.
    class Parser
      private

      def lex_list = raise(NotImplementedError, "the list lex mode")
      def lex_regexp = raise(NotImplementedError, "the regexp lex mode")
      def lex_string = raise(NotImplementedError, "the string lex mode")
      def lex_heredoc = raise(NotImplementedError, "the heredoc lex mode")
    end
  end
end
