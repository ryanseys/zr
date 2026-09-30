# frozen_string_literal: true

# `redo` in a block re-enters PAST the bindings, so the parameter keeps
# what the body assigned to it.
steps = []
[10].each do |v|
  steps << v
  if v < 12
    v += 1
    redo
  end
end
p steps

