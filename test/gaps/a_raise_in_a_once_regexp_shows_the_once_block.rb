# CRuby compiles the interpolation of a `/#{...}/o` as a block of its own,
# so a backtrace from inside it shows one more `block in` line. zr runs
# the interpolation in the frame around it.
def make(i) = /#{raise "no" if i == 1; i}/o

begin
  make(1)
rescue => e
  puts e.backtrace.map { |line| line.sub(/\A.*?:/, "") }
end
