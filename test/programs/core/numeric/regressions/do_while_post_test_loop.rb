# Prism's PM_LOOP_FLAGS_BEGIN_MODIFIER (= 4, bit 2) marks
# `begin..end while cond` / `begin..end until cond` as post-test
# loops — body runs at least once, also when the condition is
# false on entry.

ran = 0
begin
  ran += 1
end while ran > 99      # cond false on entry → post-test runs body once
puts ran                # 1

ran2 = 0
begin
  ran2 += 1
end until ran2 < 99     # cond true on entry → post-test runs body once
puts ran2               # 1

# Sanity: bare pre-test `while` with cond false on entry runs zero
# times.
ran3 = 0
while ran3 > 99 do ran3 += 1 end
puts ran3               # 0
