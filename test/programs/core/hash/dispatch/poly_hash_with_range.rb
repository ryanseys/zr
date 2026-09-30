# A Range in a mixed container: a hash literal mixes Integer values
# with Range values, and each value keeps its class. Same shape for
# mixed arrays.

# Hash form (the Rails status-symbol table shape).
STATUS_SYMBOLS = {
  success:    200..299,
  redirect:   300..399,
  missing:    404,
  not_found:  404,
  error:      500..599,
  ok:         200,
  created:    201,
  no_content: 204,
}

puts STATUS_SYMBOLS[:success]    # 200..299
puts STATUS_SYMBOLS[:ok]         # 200
puts STATUS_SYMBOLS[:created]    # 201
puts STATUS_SYMBOLS[:error]      # 500..599
puts STATUS_SYMBOLS[:not_found]  # 404

# Array form — same fundamental issue (Range crosses into poly slot).
arr = [200..299, 200, 300..399, 404]
puts arr.length                  # 4
puts arr[0]                      # 200..299
puts arr[1]                      # 200
puts arr[2]                      # 300..399
puts arr[3]                      # 404
