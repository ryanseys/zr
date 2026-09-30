def rescued
  yield 8
rescue StandardError
  :r
else
  :fell
end
def c6; rescued { |v| return v }; :no; end
p c6

