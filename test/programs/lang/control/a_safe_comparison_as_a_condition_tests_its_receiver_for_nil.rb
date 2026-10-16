# A safe call of a comparison as a condition tests its receiver for nil
# first: nil&.== nil is nil, so the loop ends and the branch is not taken.
# FileUtils.ln_sr's fu_common_components walks two paths this way.
x = [1, 2]
y = [1, 2]
i = 0
i += 1 while x[i]&.== y[i]
p i
j = 0
j += 1 while x[j]&.<(3)
p j
a = nil
p(if a&.== nil then :taken else :not end)
p(if a&.< 1 then :taken else :not end)
p(a&.==(nil) ? :taken : :not)
p((:yes unless a&.> 0))
p(1&.==(1) ? :taken : :not)
p(1&.<(0) ? :taken : :not)
k = 3
k -= 1 until (k.zero? ? nil : k)&.<= 1
p k
p(x.count { |v| v&.>= 2 })
p(a&.!= 1 || :right)
p(a&.== nil && :right)
