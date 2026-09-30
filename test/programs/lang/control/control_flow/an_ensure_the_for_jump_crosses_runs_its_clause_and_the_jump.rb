# frozen_string_literal: true

# An `ensure` the jump crosses runs its clause and the jump goes on.
def guarded(list)
  log = []
  for n in list
    begin
      next if n == 2
      break if n == 4

      log << n
    ensure
      log << [:e, n]
    end
  end
  log
end

p guarded([1, 2, 3, 4, 5])

