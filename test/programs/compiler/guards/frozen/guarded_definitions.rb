# frozen_string_literal: true

# A `class` written inside another statement is the class's whole body,
# and whether the statement runs is a run-time fact. The row still
# registers -- ids are the backend's and no class row can be minted
# while the program runs -- but concealed, so the constant appears only
# where the body actually runs.

value = 1

if value.positive?
  class Taken
    def go = :taken
  end
end

if value.negative?
  class Skipped
    def go = :skipped
  end
end

p Taken.new.go
p defined?(Skipped)

# A module reads the same way, and one nested in a guarded class body
# waits for the body around it.
unless value.zero?
  module Tools
    class Inner
      def go = :inner
    end
  end
end
p Tools::Inner.new.go

# A `def` under a guard is installed where it stands, so the branch that
# does not run writes no method.
class Host
  def base = 1
  if [].any?
    def extra = 2
  end
  if [1].any?
    def added = 3
  end
end
p Host.new.base
p Host.new.added
p Host.new.respond_to?(:extra)
p Host.instance_methods(false).sort

# A `class` written in an EXPRESSION runs where the statement does, so
# its row is declared like any other.
LAST = (class Valued
  7
end)

p LAST, Valued.name

made = module Named
  :named
end

p made, Named.name

begin
  class InBegin
    def go = :in_begin
  end
end

p InBegin.new.go
