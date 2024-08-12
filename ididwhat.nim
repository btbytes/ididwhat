import os
import osproc
import strformat
import strutils
import times

import db_connector/db_sqlite

type
  ActivityInfo = object
    appName: string
    windowTitle: string
    url: string

proc createDatabase() =
  let db = open("tracker.db", "", "", "")
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS activities (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
      app_name TEXT NOT NULL,
      window_title TEXT,
      url TEXT
    )
  """)
  db.close()
  echo "Database and table created successfully."

proc runAppleScript(script: string): string =
  let (output, exitCode) = execCmdEx("osascript -e " & quoteShell(script))
  if exitCode == 0:
    result = output.strip()
  else:
    result = ""

proc getActiveWindowInfo(): ActivityInfo =
  let appNameScript = """
    tell application "System Events"
      set frontApp to name of first application process whose frontmost is true
    end tell
  """
  let appName = runAppleScript(appNameScript)

  var windowTitle, url: string
  if appName in ["Safari", "Google Chrome", "Firefox", "Brave Browser"]:
    let browserScript = fmt"""
      tell application "{appName}"
        set currentTab to active tab of front window
        return (URL of currentTab) & "|" & (name of currentTab)
      end tell
    """
    let browserInfo = runAppleScript(browserScript)
    if "|" in browserInfo:
      let parts = browserInfo.split('|', 1)
      url = parts[0].strip()
      windowTitle = parts[1].strip()
  else:
    let titleScript = fmt"""
      tell application "System Events"
        tell process "{appName}"
          try
            return name of front window
          on error
            return "No window title available"
          end try
        end tell
      end tell
    """
    windowTitle = runAppleScript(titleScript)
    if windowTitle == "":
      windowTitle = "No window title available"

  result = ActivityInfo(appName: appName, windowTitle: windowTitle, url: url)

proc insertActivity(db: DbConn, timestamp: string, appName, windowTitle, url: string) =
  db.exec(sql"INSERT INTO activities (timestamp, app_name, window_title, url) VALUES (?, ?, ?, ?)",
          timestamp, appName, windowTitle, url)
  echo "Inserted: ", timestamp, ", ", appName, ", ", windowTitle, ", ", url

proc main() =
  createDatabase()
  let db = open("tracker.db", "", "", "")

  var
    lastAppName, lastWindowTitle, lastUrl: string
    lastInsertTime: float

  try:
    while true:
      let currentTime = now().format("yyyy-MM-dd HH:mm:ss")
      let info = getActiveWindowInfo()

      if info.appName != lastAppName or
         info.windowTitle != lastWindowTitle or
         info.url != lastUrl or
         (lastInsertTime > 0 and epochTime() - lastInsertTime >= 1):

        insertActivity(db, currentTime, info.appName, info.windowTitle, info.url)

        lastAppName = info.appName
        lastWindowTitle = info.windowTitle
        lastUrl = info.url
        lastInsertTime = epochTime()

      sleep(1000) # Sleep for 1 second
  except:
    echo "Tracking stopped."
  finally:
    db.close()

when isMainModule:
  main()
