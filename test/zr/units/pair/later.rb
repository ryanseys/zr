# One file of a three-file unit: a def main calls, calling back into main's file.
sig [Word] => Word
machine def later(n)
  twice(n) + 1
end
