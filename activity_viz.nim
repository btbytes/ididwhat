import algorithm
import sequtils
import strformat
import strutils
import tables
import times
import uri

import db_connector/db_sqlite

const
  MaxGap = 10 * 60 # Maximum gap in seconds (10 minutes) before considering it as inactivity
  MaxActivityLength = 50 # Maximum length for activity names before truncation

type
  Gap = tuple[start, endTime: DateTime, duration: int]

proc getDomain(url: string): string =
  try:
    result = parseUri(url).hostname
  except:
    result = "Unknown"

proc truncateString(s: string, maxLength: int): string =
  if s.len > maxLength:
    result = s[0..<maxLength-3] & "..."
  else:
    result = s

proc formatTime(seconds: int): string =
  let
    hours = seconds div 3600
    minutes = (seconds mod 3600) div 60
    secs = seconds mod 60
  result = fmt"{hours}h {minutes}m {secs}s"

proc processActivities(db: DbConn, startTime, endTime: DateTime): (Table[string,
    float], float, seq[Gap]) =
  var
    activitySummary = initTable[string, float]()
    totalDuration: float = 0
    lastTimestamp: DateTime
    lastActivity: string
    gaps: seq[Gap] = @[]

  for row in db.rows(sql"SELECT * FROM activities WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
                     startTime.format("yyyy-MM-dd HH:mm:ss"), endTime.format(
                         "yyyy-MM-dd HH:mm:ss")):
    let
      timestamp = parse(row[1], "yyyy-MM-dd HH:mm:ss")
      appName = row[2]
      windowTitle = row[3]
      url = row[4]

    var activity = if appName in ["Brave Browser", "Google Chrome", "Safari",
        "Firefox"]: getDomain(url) else: appName

    if not lastTimestamp.isInitialized:
      lastTimestamp = timestamp
      lastActivity = activity
      continue

    let duration = (timestamp - lastTimestamp).inSeconds.float

    if duration > MaxGap.float or lastActivity == "loginwindow":
      gaps.add((lastTimestamp, timestamp, duration.int))
    elif lastActivity != "loginwindow":
      activitySummary.mgetOrPut(lastActivity, 0.0) += duration
      totalDuration += duration

    lastTimestamp = timestamp
    lastActivity = activity

  result = (activitySummary, totalDuration, gaps)

proc summary(db: DbConn, hours, minutes: int) =
  let
    now = now()
    timeDelta = if hours > 0: hours.hours else: minutes.minutes
    startTime = now - timeDelta

  let (activitySummary, totalDuration, gaps) = processActivities(db, startTime, now)

  echo fmt"Activity Summary for the last {hours}:{minutes}"

  let
    requestedDuration = timeDelta.seconds.float
    totalGapTime = requestedDuration - totalDuration
    coveragePercentage = (totalDuration / requestedDuration) * 100

  echo fmt"Total tracked time: {formatTime(totalDuration.int)}"
  echo fmt"Requested duration: {formatTime(requestedDuration.int)}"
  echo fmt"Total gap time: {formatTime(totalGapTime.int)}"
  echo fmt"Tracking coverage: {coveragePercentage:.2f}%"

  if gaps.len > 0:
    echo fmt"Detected gaps within tracked time: {gaps.len}"
    echo "Largest gaps within tracked time:"
    for gap in gaps.sortedByIt(it.duration)[0..min(4, gaps.len - 1)]:
      echo fmt"  From {gap.start} to {gap.endTime} ({formatTime(gap.duration)})"

  echo "Top activities (% of tracked time, excluding sleep):"
  var sortedActivities = toSeq(activitySummary.pairs).sortedByIt(it[1])
  sortedActivities.reverse()

  for (activity, duration) in sortedActivities:
    if activity != "loginwindow":
      let percentage = (duration / totalDuration) * 100
      if percentage > 0.5:
        echo fmt"  {truncateString(activity, MaxActivityLength):<50} {formatTime(duration.int):>15} {percentage:>6.2f}%"

  let sleepTime = gaps.filterIt(it.duration > MaxGap).mapIt(it.duration).foldl(
      a + b, 0)
  echo fmt"Note: Your device was likely asleep or locked for approximately {formatTime(sleepTime)}."

when isMainModule:
  let db = open("tracker.db", "", "", "")
  summary(db, 1, 0) # Default to 1 hour summary
  db.close()
