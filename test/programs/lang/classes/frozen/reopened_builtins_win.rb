# frozen_string_literal: true

# Integer arithmetic and comparison take an inline fast path, and `puts`
# folds to the runtime's own writer. A user definition has to be able to
# take either of them back: a reopen that redefines an operator anywhere
# on Integer's fast-path MRO stands the whole fast path down, and any
# `puts` this program defines stands the fold down.

class Integer
  def +(other) = "int-plus(#{other})"
end

p 1 + 2
p 1 - 2
p 1 < 2

module Comparable
  def <=>(other) = :spaceship
end

p(3 <=> 4)
p 5 == 5

class Logger
  def puts(msg) = "logged: #{msg}"

  def run = puts("hi")
end

p Logger.new.run

module Kernel
  def puts(*a) = $stdout.write("K:#{a.join(",")}\n")
end

puts "a", "b"
