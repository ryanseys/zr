# all?, any?, none? and one? answer an empty Array before they warn
# that a block with a pattern is not used.
$stderr = $stdout
%i[all? any? none? one?].each do |m|
  p [m, [].send(m, 1) { true }]
  p [m, [1].send(m, 1) { true }]
  p [m, {}.send(m, 1) { true }] if m == :any?
  p [m, { a: 1 }.send(m, [:a, 1]) { true }] if m == :any?
end
