# A module the program opened first is the one the extension fills.
module Etc
  MINE = 1
end
require "etc"
p Etc::MINE
p Etc.respond_to?(:getlogin)
