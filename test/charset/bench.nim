import std/envvars
import std/math
import std/streams
import std/strutils
import std/times

import encoding/charset
import encoding/decoder
import encoding/encoder

proc main() =
  let file = getEnv("BENCH_FILE")
  let cs = getCharset(getEnv("BENCH_CHARSET"))
  let iter = parseInt(getEnv("BENCH_ITER"))
  let fail_outdir = getEnv("BENCH_ERROR_OUTDIR")
  let ss = newFileStream(file).readAll()
  let devnull = open("/dev/null", fmWrite)
  # check
  let check0 = ss.decodeAll(cs)
  let check = check0.encodeAll(cs)
  if check != ss:
    eprint "ERROR: equivalence check failed"
    if fail_outdir != "":
      let os0 = newFileStream("/tmp/bench_fail_output0", fmWrite)
      os0.write(check0)
      let os1 = newFileStream("/tmp/bench_fail_output1", fmWrite)
      os1.write(check)
      os0.close()
      os1.close()
    quit(1)

  echo "Starting benchmark for ", file, " charset ", cs
  let startAll = cpuTime()
  var times = 0f64
  var low = float64.high
  var high = 0f64
  for i in 0 ..< iter:
    let startIt = cpuTime()
    let res = ss.decodeAll(cs)
    devnull.write(res)
    let endIt = cpuTime()
    let time = endIt - startIt
    low = min(low, time)
    high = max(high, time)
    times += endIt - startIt
  let finishAll = cpuTime()
  echo "Done in ", finishAll - startAll, "ms, avg ", (times / float64(iter)).round(6),
    " lowest ", low.round(6), " highest ", high.round(6)

main()
