## module to use to bridge files for multiple backends
## 
## defines a mini unittest for nimscript

when defined(nimscript):
  type FailedTests* = object of Defect

  var anyFailedTests* = false
  # failed tests list could be redundant with runTests task

  template runTests*(body) =
    body
    if anyFailedTests:
      raise newException(FailedTests, "failed tests")
else:
  template runTests*(body) =
    body

when defined(js):
  type NativeString = cstring
else:
  type NativeString = string

proc properFile*(str: NativeString, addSlash = false): string =
  let len = str.len
  when defined(nimscript):
    result = newStringOfCap(len + int(addSlash))
    for c in str:
      result.add(if c == '\\': '/' else: c)
    if addSlash: result.add('/')
  else:
    result = newString(len + int(addSlash))
    for i in 0 ..< len:
      let c = str[i]
      result[i] = if c == '\\': '/' else: c
    if addSlash: result[len] = '/'

proc properDir*(str: NativeString): string {.inline.} =
  result = properFile(str, str[str.len - 1] notin {'/', '\\'})

when defined(js):
  import unittest
  export unittest except test, suite
  
  template test*(name, body): untyped =
    unittest.test(name):
      try:
        body
      except:
        let e = getCurrentException()
        if e.isNil:
          {.emit: "console.trace(EXCEPTION);".}
          fail()
        else:
          raise e
  
  type FileSystem* = ref object
  var fs* {.importc, nodecl.}: FileSystem
  {.emit: "const fs = require(\"fs\");".}
  using fs: FileSystem
  proc readdirSync*(fs; path: NativeString): seq[NativeString] {.importjs: "#.$1(@)".}
  proc readFileSync*(fs; path: NativeString, encoding = NativeString("utf8")): NativeString {.importjs: "#.$1(@)".}
  proc writeFileSync*(fs; path, data: NativeString, encoding = NativeString("utf8")) {.importjs: "#.$1(@)".}

  template read*(path: NativeString): string = $fs.readFileSync(path)
  template write*(path, data: NativeString) = fs.writeFileSync(path, data)

  template read*(path: string): string =
    read(NativeString(path))
  template write*(path, data: string | NativeString) =
    write(NativeString(path), NativeString(data))

  proc `&`(a, b: cstring): cstring {.importjs: "(# + #)".}

  iterator files*(dir: NativeString): tuple[noDir: string, withDir: NativeString] =
    let prefix = cstring properDir(dir)
    let files = fs.readdirSync(dir)
    for file in files:
      yield ($file, prefix & file)
else:
  when defined(nimscript):
    # mini unittest
    type Test* = object
      name*: string
      checkpoints*: seq[string]
      failed*: bool
    
    var currentTest*: Test # threadvar

    import macros
    macro check*(b: untyped) =
      if b.kind == nnkStmtList:
        result = newStmtList()
        for c in b:
          result.add getAst(check(c))
      else:
        let str = newLit(repr(b))
        result = quote do:
          if not `b`:
            echo "Check failed: " & `str`
            fail()

    proc checkpoint*(s: string) = currentTest.checkpoints.add(s)

    proc fail*() =
      when false:
        # this is so stupid
        writeFile("nims_test_failed", "") 
      anyFailedTests = true
      currentTest.failed = true
    
    template test*(testName, testBody) =
      block:
        currentTest = Test(name: testName)
        
        try:
          testBody
        except:
          checkpoint("Unhandled exception")
          fail()

        if currentTest.failed:
          for c in currentTest.checkpoints:
            echo c
          echo "[FAILED] " & testName
          quit(1)
        else:
          echo "[OK] " & testName
  else:
    import unittest
    export unittest except suite

  from os import walkDir, PathComponent

  iterator files*(dir: NativeString): tuple[noDir: string, withDir: NativeString] =
    let prefix = properDir(dir)
    for (kind, file) in walkDir(dir, relative = true):
      if kind == pcFile:
        yield (file, prefix & file)

  template read*(path: NativeString): string = readFile(path)
  template write*(path, data: NativeString) = writeFile(path, data)
