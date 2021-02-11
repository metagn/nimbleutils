## personal library for nimscript tasks

import os, strutils

when not defined(nimscript):
  # {.warning: "nimbleutils is meant to be used inside nimscript".}
  import osproc
  let srcDir = "src"
  proc exec(command: string) =
    let (output, exitCode) = execCmdEx(command)
    if exitCode != 0:
      raise newException(OSError, "FAILED: " & command)
    echo output
  template cpFile(src, dest: string) =
    copyFile(src, dest)
  template rmFile(file: string) =
    removeFile(file)

proc buildDocs*(
  gitUrl = "", gitCommit = "master", gitDevel = "master";
  extraOptions = "", outDir = "docs") =
  ## build docs for all modules in source folder
  echo "Building docs:"
  for f in walkDirRec(srcDir):
    if f.endsWith(".nim"):
      exec "nim doc" & (
        if gitUrl.len == 0:
          ""
        else:
          " --git.url:" & gitUrl &
          " --git.commit:" & gitCommit &
          " --git.devel:" & gitDevel) &
        " --outdir:" & outDir &
        " " & extraOptions &
        " " & f

type Backend* = enum
  c, cpp, objc, js, nims

proc runTests*(backends: set[Backend] = {c},
  testsDir = "tests", recursiveDir = false,
  useRunCommand = false, extraOptions = "",
  hintsOff = true, warningsOff = false,
  nimsSuffix = "_nims", backendExtraOptions = default(array[Backend, string]),
  optionCombos = @[""]) =
  ## run tests for multiple backends at the same time
  ## 
  ## `useRunCommand` is whether to use nim r or nim c -r,
  ## `nimsSuffix` is the suffix to add to temporary nims files to distinguish
  ## from normal nim sources
  ## 
  ## `optionCombos` are possible extra option combos, should include
  ## `""` for no extra options
  echo "Running tests:"
  for fn in walkDirRec(testsDir, followFilter = if recursiveDir: {pcDir} else: {}):
    if (let (_, name, ext) = splitFile(fn);
      name[0] == 't' and ext == ".nim"):
      let noExt = fn[0..^(ext.len + 1)]
      echo "Test: ", name
      var failedBackends: set[Backend]
      for backend in backends:
        echo "Backend: ", backend
        let cmd =
          if backend == nims:
            "e"
          elif useRunCommand:
            "r --backend:" & $backend
          else:
            $backend & " --run"
        template runTest(extraOpts: string = "", file: string = fn) =
          var testFailed = false
          let fullCmd = "nim " & cmd &
            (if hintsOff: " --hints:off" else: "") &
            (if warningsOff: " --warnings:off" else: "") &
            " --path:. " & extraOpts &
            " " & extraOptions &
            " " & backendExtraOptions[backend] &
            " " & file
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
            failedBackends.incl(backend)
            echo "Failed command: ", fullCmd
          else:
            echo "Passed command: ", fullCmd
        template runCombos(extraOpts: string = "", file: string = fn) =
          for combo in optionCombos:
            if combo.len != 0:
              echo "Testing for options: ", combo
            runTest(combo & " " & extraOpts, file)
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
          let nimsFile = noExt & nimsSuffix & ".nims"
          removeAfter(nimsFile):
            # maybe rename and rename back here
            cpFile(fn, nimsFile)
            runCombos(file = nimsFile)
      if failedBackends == {}:
        echo "Passed: ", name
      else:
        echo "Failed: ", name, ", backends: ", ($failedBackends)[1..^2]
