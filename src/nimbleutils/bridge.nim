## module to use to bridge files for multiple backends

when defined(nimscript):
  type FailedTests* = object of Defect

  var anyFailedTests* = false
  # maybe replace with failed tests list, but would be redundant

  template runTests*(body) =
    body
    if anyFailedTests:
      raise newException(FailedTests, "failed tests")
else:
  template runTests*(body) =
    body
