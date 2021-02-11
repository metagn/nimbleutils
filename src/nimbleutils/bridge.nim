## module to use to bridge files for multiple backends

when defined(nimscript):
  type FailedTests* = object of Defect

  var anyFailedTests* = false

  template runTests*(body) =
    body
    if programResult != 0:
      raise newException(FailedTests, "failed tests")
else:
  template runTests*(body) =
    body
