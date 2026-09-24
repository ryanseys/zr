# frozen_string_literal: true

require "cgi/escape"

# The one escape ERB ships as a C extension, in ruby. Rails is expected
# not to stand over this one, which is why ERB keeps it apart from
# `ERB::Util#html_escape`.
module ERB::Escape
  def html_escape(s) = CGI.escapeHTML(s.to_s)
  module_function :html_escape
end
