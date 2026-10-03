# One file of a three-file unit: a def main calls, calling back into main's file.
module Zr::Kern
  #: (word) -> word
  def later(n)
    twice(n) + 1
  end
end
