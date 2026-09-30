# A multi-step dig stops at nil and raises TypeError on a step that cannot be
# dug. It does not answer the scalar that the first step found.
begin; p [1].dig(0, 0); rescue TypeError => e; p e.class; end
p [[1, 2], [3]].dig(0, 1)
p [[1, 2]].dig(5, 0)
p [[1, 2]].dig(0, 9)
p({ a: { b: 1 } }.dig(:a, :b))
p [1].dig(0)
h = { a: [1, 2] }
p h.dig(:a, 1)
begin; p({ a: 1 }.dig(:a, :b)); rescue TypeError => e; p e.class; end
