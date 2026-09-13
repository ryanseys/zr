# frozen_string_literal: true

COUNTED_RUNS = (defined?(COUNTED_RUNS) ? COUNTED_RUNS : 0) + 1
puts "counted ran"

module Counted
  def self.mark = :counted
end
