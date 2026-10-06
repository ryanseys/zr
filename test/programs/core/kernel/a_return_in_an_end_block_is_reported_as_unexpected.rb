# A return out of an END block is reported as the file and "unexpected
# return", and the next END block still runs.
END { n }
END { return }
