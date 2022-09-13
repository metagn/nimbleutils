## personal library for nimscript tasks

import os, strutils, sequtils

when not defined(nimscript):
  # {.warning: "nimbleutils is meant to be used inside nimscript".}
  import osproc
  proc exec(command: string) =
    let (output, exitCode) = execCmdEx(command)
    if exitCode != 0:
      raise newException(OSError, "FAILED: " & command)
    echo output
  template cpFile(src, dest: string) =
    copyFile(src, dest)
  template rmFile(file: string) =
    removeFile(file)

type Dir* = string
type FilePath* = string

type DocsOptions* = object
  gitUrl*, gitCommit*, gitDevel*: string
  outDir*: Dir
  extraOptions*: string

proc docsOptions*(
  gitUrl = "", gitCommit = "master", gitDevel = "master",
  extraOptions = "", outDir = "docs"): DocsOptions =
  result.gitUrl = gitUrl
  result.gitCommit = gitCommit
  result.gitDevel = gitDevel
  result.outDir = outDir
  result.extraOptions = extraOptions

proc fileBuildDocs*(filename: FilePath,
  options = docsOptions()) =
  ## build docs for single file
  echo "Building docs for ", filename
  exec "nim doc" & (
    if options.gitUrl.len == 0:
      ""
    else:
      " --git.url:" & options.gitUrl &
      " --git.commit:" & options.gitCommit &
      " --git.devel:" & options.gitDevel) &
    " --outdir:" & options.outDir &
    " " & options.extraOptions &
    " " & filename

proc buildDocs*(dir: seq[FilePath] | Dir = "src", 
  options = docsOptions()) =
  ## build docs for all modules in source folder
  ## if dir is seq of strings, it is a seq of files to make docs of
  if not dirExists(dir):
    echo "Cannot build docs, directory '", dir, "' does not exist"
    return

  echo "Building docs:"
  when dir is Dir:
    for f in walkDirRec(dir):
      if f.endsWith(".nim"):
        fileBuildDocs(f, options)
  else:
    for f in dir:
      fileBuildDocs(f, options)

proc buildDocs*(dir: seq[FilePath] | Dir = "src", 
  gitUrl = "", gitCommit = "master", gitDevel = "master",
  extraOptions = "", outDir = "docs") =
  ## build docs for all modules in source folder
  ## if dir is seq of strings, it is a seq of files to make docs of
  buildDocs(dir, docsOptions(gitUrl, gitCommit, gitDevel, extraOptions, outDir))

type Backend* = enum
  c, cpp, objc, js, nims

type TestOptions* = object
  backends*: set[Backend]
  useRunCommand*: bool
    ## whether to use `nim r` vs `nim c -r`
  hintsOff*, warningsOff*: bool
  nimsSuffix*: string
    ## suffix for nims file to create if nims is as a backend
  optionCombos*: seq[string]
    ## possible extra option combos, should include
    ## `""` for no extra options
  extraOptions*: string
  backendExtraOptions*: array[Backend, string]

proc testOptions*(backends: set[Backend] = {c},
  useRunCommand = false, extraOptions = "",
  hintsOff = true, warningsOff = false,
  nimsSuffix = "_nims", backendExtraOptions = default(array[Backend, string]),
  optionCombos = @[""]): TestOptions =
  result.backends = backends
  result.useRunCommand = useRunCommand
  result.extraOptions = extraOptions
  result.hintsOff = hintsOff
  result.warningsOff = warningsOff
  result.nimsSuffix = nimsSuffix
  result.backendExtraOptions = backendExtraOptions
  result.optionCombos = optionCombos

proc runTest*(file: FilePath, options = testOptions()): tuple[name: string, failedBackends: set[Backend]] =
  ## runs single test file
  let (dir, name, _) = splitFile(file)
  result.name = name
  let noExt = dir / name
  echo "Test: ", name
  for backend in options.backends:
    echo "Backend: ", backend
    let cmd =
      if backend == nims:
        "e"
      elif options.useRunCommand:
        "r --backend:" & $backend
      else:
        $backend & " --run"
    template run(extraOpts: string = "", filename: string = file) =
      var testFailed = false
      let fullCmd = "nim " & cmd &
        (if options.hintsOff: " --hints:off" else: "") &
        (if options.warningsOff: " --warnings:off" else: "") &
        " --path:. " & extraOpts &
        " " & options.extraOptions &
        " " & options.backendExtraOptions[backend] &
        " " & filename
      try:
        exec fullCmd
        when false:
          const nimsTestFailFile = "nims_test_failed"
          if backend == nims and fileExists(nimsTestFailFile):
            testFailed = true
            rmFile(nimsTestFailFile)
      except:
        # exec exit code 1
        testFailed = true
      if testFailed:
        result.failedBackends.incl(backend)
        echo "Command failed: ", fullCmd
      else:
        echo "Command passed: ", fullCmd
    template runCombos(extraOpts: string = "", filename: string = file) =
      for combo in options.optionCombos:
        if combo.len != 0:
          echo "Testing for options: ", combo
        run(combo & " " & extraOpts, filename)
    template removeAfter(toRemove: string, body: untyped) =
      let toRemoveExisted = fileExists(toRemove)
      body
      if not toRemoveExisted and fileExists(toRemove):
        rmFile(toRemove)
    case backend
    of c, cpp, objc:
      let exe = if ExeExt == "": noExt else: noExt & "." & ExeExt 
      removeAfter(exe):
        runCombos()
    of js:
      let output = noExt & ".js" 
      removeAfter(output):
        runCombos(extraOpts = "-d:nodejs")
    of nims:
      let nimsFile = noExt & options.nimsSuffix & ".nims"
      removeAfter(nimsFile):
        # maybe rename and rename back here
        cpFile(file, nimsFile)
        runCombos(filename = nimsFile)
  if result.failedBackends == {}:
    echo "Test passed: ", name
  else:
    echo "Test failed: ", name, ", backends: ", ($result.failedBackends)[1..^2]

proc runTests*(testsDir: Dir | seq[FilePath] = "tests",
  recursiveDir = false, options = testOptions()) =
  ## run tests for multiple backends at the same time
  echo "Running tests:"
  var
    failedBackends: set[Backend]
    failedTests: seq[string]
  template doTest(fn: FilePath) =
    let testResults = runTest(fn, options)
    if testResults.failedBackends != {}:
      failedBackends.incl(testResults.failedBackends)
      failedTests.add(testResults.name)
  when testsDir is Dir:
    for fn in walkDirRec(testsDir, followFilter = if recursiveDir: {pcDir} else: {}):
      if (let (_, name, ext) = splitFile(fn);
        name[0] == 't' and ext == ".nim"):
        doTest(fn)
  else:
    for fn in testsDir:
      doTest(fn)
  if failedTests.len == 0:
    echo "All tests passed"
  else:
    echo "Failed tests: ", failedTests.join(", ")
    echo "Failed backends: ", failedBackends.toSeq().join(", ")
    quit(1)

proc runTests*(testsDir: Dir | seq[FilePath] = "tests",
  recursiveDir = false,
  backends: set[Backend] = {c},
  useRunCommand = false, extraOptions = "",
  hintsOff = true, warningsOff = false,
  nimsSuffix = "_nims", backendExtraOptions = default(array[Backend, string]),
  optionCombos = @[""]) =
  ## run tests for multiple backends at the same time
  runTests(testsDir, recursiveDir, testOptions(backends, useRunCommand,
    extraOptions, hintsOff, warningsOff, nimsSuffix, backendExtraOptions, optionCombos))
