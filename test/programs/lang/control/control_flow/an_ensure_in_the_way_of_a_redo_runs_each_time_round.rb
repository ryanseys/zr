# frozen_string_literal: true

# ...and an `ensure` in the way runs each time round.
log = []
attempts = 0
[1].each do |_|
  begin
    attempts += 1
    redo if attempts < 3
  ensure
    log << attempts
  end
end
p log

