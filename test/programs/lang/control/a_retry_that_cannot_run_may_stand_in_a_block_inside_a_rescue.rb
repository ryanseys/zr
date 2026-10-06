# A retry that cannot run is no error: the parse drops it with its
# dead branch before it asks whether the retry is where one may be.
begin
  raise "y"
rescue
  [1].each { retry if false }
  p :no_retry
end
