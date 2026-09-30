# frozen_string_literal: true

module Zr
  # Whether the environment variable `name` is on. Unset or empty gives
  # `default`, "0" is off, and any other value is on.
  def self.flag?(name, default: false)
    value = ENV[name]
    value.nil? || value.empty? ? default : value != "0"
  end
end
