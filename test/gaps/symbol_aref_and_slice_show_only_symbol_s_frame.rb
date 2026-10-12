# Symbol#[] and #slice run rb_str_aref in C, so an error shows only
# 'Symbol#[]' or 'Symbol#slice'. zr runs String#[] through a saved
# UnboundMethod (so a program's String#[] does not change Symbol's), and
# the builtin frame of bind_call between them makes String#[] show:
# 'String#[]'. A helper's direct call of a builtin on a core value hides
# that frame (zr_frame_shown_p), but a call through bind_call does not.
def label
  yield
rescue StandardError => e
  p e.backtrace_locations.first.label
end

label { :abc[nil] }
label { :abc.slice(1, 2, 3) }
label { :abc[] }
label { :abc["a", "b"] }
