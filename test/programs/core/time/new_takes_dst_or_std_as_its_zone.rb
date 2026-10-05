# Time.new takes :dst or :std as its zone: local time, with that one of
# two offsets that fit an hour that a clock change repeats.
ENV["TZ"] = "America/Lima"
p Time.new(1990, 3, 31, 23, 30, 0, :dst).to_s, Time.new(1990, 3, 31, 23, 30, 0, :std).to_s, Time.new(1990, 3, 31, 23, 30, 0).to_s
ENV["TZ"] = "America/New_York"
p Time.new(2023, 11, 5, 1, 30, 0, :dst).to_s, Time.new(2023, 11, 5, 1, 30, 0, :std).to_s, Time.new(2023, 7, 1, 12, 0, 0, :std).to_s
p Time.local(30, 30, 1, 5, 11, 2023, nil, nil, true, nil).to_s, Time.local(30, 30, 1, 5, 11, 2023, nil, nil, false, nil).to_s
