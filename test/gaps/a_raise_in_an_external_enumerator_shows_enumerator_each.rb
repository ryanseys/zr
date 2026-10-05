# A raise inside an external enumerator's fiber shows the C frame
# Enumerator#each at its base, with the file and no line. zr hides that
# frame, as a helper of the enumerator calls it.
def foo
  return to_enum(__method__) unless block_given?
  raise
  yield 1
end
begin
  foo.next
rescue => e
  p e.backtrace
end
