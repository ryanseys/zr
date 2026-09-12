# frozen_string_literal: true

# `require "io/console/size"`: the terminal's size, and a size to fall
# back on. ruby keeps these in their own feature, which `io/console`
# alone does not load, and which loads `io/console` itself.
require "io/console"

class IO
  # LINES and COLUMNS from the environment, and 25 by 80 when neither
  # names a positive number.
  def self.default_console_size
    lines = ENV["LINES"].to_i
    columns = ENV["COLUMNS"].to_i
    [lines.positive? ? lines : 25, columns.positive? ? columns : 80]
  end

  # The terminal's own size. A process with no terminal has no winsize
  # to ask for, and falls back on the environment.
  def self.console_size
    console.winsize
  rescue NoMethodError
    default_console_size
  end
end
