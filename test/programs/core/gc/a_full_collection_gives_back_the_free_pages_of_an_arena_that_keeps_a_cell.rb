# A chain of two million cells, with one cell in every 8,192 kept. After
# the chain goes and a full collection runs, zr gives back the pages of
# free cells around each kept one (164 MB resident -> 48 MB); ruby's
# pages stay resident in its malloc. The kept cells keep their contents,
# and a new chain takes the pages again.
def rss_kb
  status = "/proc/self/status"
  return File.foreach(status).find { |line| line.start_with?("VmRSS:") }.split[1].to_i if File.exist?(status)

  `ps -o rss= -p #{$$}`.to_i
end

keep = []
head = nil
2_000_000.times do |i|
  head = [head, i]
  keep << head if i % 8192 == 0
end
keep.each { |cell| cell[0] = nil }
peak = rss_kb
head = nil
GC.start
GC.start
p rss_kb <= peak
p keep.size
p keep.sum { |cell| cell[1] } == (0...2_000_000).step(8192).sum

again = nil
2_000_000.times { |i| again = [again, i.to_s] }
n = 0
cell = again
while cell
  n += 1 if cell[1] == (2_000_000 - 1 - n).to_s
  cell = cell[0]
end
p n
p keep.all? { |c| c[0].nil? && c[1] % 8192 == 0 }
