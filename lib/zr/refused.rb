# frozen_string_literal: true

module Zr
  # Marks an exception as a refusal: the program uses a form that the
  # marked stage does not support, as opposed to a bug in that stage. A
  # refusal keeps the superclass its stage already raises (`StandardError`,
  # `Backend::Refused`, `NotImplementedError`, ...), so exit codes
  # (`CLI.lower`), the spec tier split (`Spec::REFUSALS`) and the cc
  # fallbacks (`Native::Build`) keep matching on that superclass. `include
  # Zr::Refusal` only lets code ask a class or instance whether it means
  # this, without naming every stage's own `Refused`.
  module Refusal; end

  # The program uses a form that zr does not support. The message gives
  # the form, the file and the line. `zr` exits with status 3
  # (`CLI::REFUSED`), and the spec tier skips the example.
  class Refused < StandardError
    include Refusal
  end
end
