# frozen_string_literal: true

module Zr
  # The program uses a form that zr does not support. The message gives
  # the form, the file and the line. `zr` exits with status 3
  # (`CLI::REFUSED`), and the spec tier skips the example.
  class Refused < StandardError; end
end
