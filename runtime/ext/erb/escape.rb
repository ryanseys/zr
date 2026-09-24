# frozen_string_literal: true

require "cgi/escape"

# The one escape that ERB ships as a C extension, in ruby. Rails is not
# expected to override this one, which is why ERB keeps it separate from
# `ERB::Util#html_escape`.
module ERB::Escape
  def html_escape(s) = CGI.escapeHTML(s.to_s)
  module_function :html_escape
end
