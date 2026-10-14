# frozen_string_literal: true

module Zr
  module Test
    # Whether the variable `name` is on, read as every test flag reads:
    # unset or empty gives `default`, "0" is off, and any other value is
    # on. It loads nothing, so the coverage run, the program tests and the
    # Rakefile can read a flag before zr loads.
    def self.flag?(name, default: false)
      value = ENV[name]
      value.nil? || value.empty? ? default : value != "0"
    end
  end
end
