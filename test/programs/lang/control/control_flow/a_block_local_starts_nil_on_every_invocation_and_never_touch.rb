# frozen_string_literal: true

# A block-local starts nil every invocation and never touches the name
# outside it.
scratch = :outer
seen = []
[1, 2].each do |n; scratch|
  seen << scratch
  scratch = n
  seen << scratch
end
p seen, scratch

