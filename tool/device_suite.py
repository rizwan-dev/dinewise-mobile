"""Runs an on-device suite from integration_test/ and saves a screenshot of the device each time
the test prints SHOT:<name>.

    python3 tool/device_suite.py <device id> <test file> <shots dir> [flutter test args...]

<device id> is an iOS simulator UDID or an Android emulator serial (emulator-5554). The local
stack is `docker compose` in the web repo; set DINEWISE_API_DIR to that checkout and
DINEWISE_COMPOSE_PROJECT to its compose project name.

    OFFLINE=1   watch for the order noted "Please ring the bell" (customer suite, with
                --dart-define=OFFLINE_CHECK=true) and stop the API for 20 s, then start it.
    ASAP_NOW=1  after closing time an ASAP order is due at the next opening and waits under
                "Scheduled for later"; bring ASAP orders placed during the run forward to half
                an hour from now in the LOCAL database, as if the kitchen were open (kitchen suite).
"""
import os
import subprocess
import sys
import threading
import time

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = os.environ.get("DINEWISE_API_DIR", os.path.join(os.path.dirname(APP), "dinewise"))
PROJECT = os.environ.get("DINEWISE_COMPOSE_PROJECT", "dinewise")
udid, test, shots = sys.argv[1], sys.argv[2], sys.argv[3]
extra = sys.argv[4:]
os.makedirs(shots, exist_ok=True)

ADB = os.path.join(os.environ.get("ANDROID_HOME", os.path.expanduser("~/Library/Android/sdk")), "platform-tools", "adb")
android = udid.startswith("emulator")


def demo_mode():
    """Android's system UI demo mode: a clean, fixed status bar for screenshots."""
    sh = [ADB, "-s", udid, "shell"]
    subprocess.run(sh + ["settings", "put", "global", "sysui_demo_allowed", "1"])
    for extra in (["-e", "command", "enter"],
                  ["-e", "command", "clock", "-e", "hhmm", "0941"],
                  ["-e", "command", "battery", "-e", "level", "100", "-e", "plugged", "false"],
                  ["-e", "command", "network", "-e", "wifi", "show", "-e", "level", "4"],
                  ["-e", "command", "network", "-e", "mobile", "show", "-e", "level", "4", "-e", "datatype", "none"],
                  ["-e", "command", "notifications", "-e", "visible", "false"]):
        subprocess.run(sh + ["am", "broadcast", "-a", "com.android.systemui.demo", *extra], capture_output=True)


if android:
    demo_mode()
else:
  subprocess.run(["xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41",
                "--batteryState", "charged", "--batteryLevel", "100", "--wifiBars", "3",
                "--cellularMode", "active", "--cellularBars", "4"], check=False)


def offline_watcher():
    while True:
        out = subprocess.run(
            ["docker", "compose", "-p", PROJECT, "exec", "-T", "db", "psql", "-U", "dinewise",
             "-d", "dinewise", "-tAc",
             "select count(*) from orders where notes='Please ring the bell' and status='PLACED'"],
            capture_output=True, text=True).stdout.strip()
        if out and out != "0":
            time.sleep(6)
            print(">>> stopping the API", flush=True)
            subprocess.run(["docker", "compose", "--project-directory", API, "-p", PROJECT, "stop", "web"])
            time.sleep(20)
            print(">>> starting the API", flush=True)
            subprocess.run(["docker", "compose", "--project-directory", API, "-p", PROJECT, "start", "web"])
            return
        time.sleep(2)


def asap_watcher():
    """After closing time an ASAP order is due tomorrow and waits under "Scheduled for later". For
    the kitchen suite, ASAP orders placed during the run are brought forward to half an hour from
    now in the local database, as if the kitchen were open."""
    sql = ("update orders set slot_start = date_trunc('minute', now()) + interval '30 min' "
           "where not scheduled and created_at > now() - interval '30 min' "
           "and slot_start > now() + interval '55 min' and status = 'PLACED'")
    while True:
        subprocess.run(["docker", "compose", "-p", PROJECT, "exec", "-T", "db", "psql", "-U",
                        "dinewise", "-d", "dinewise", "-tAc", sql], capture_output=True)
        time.sleep(1)


if os.environ.get("ASAP_NOW") == "1":
    threading.Thread(target=asap_watcher, daemon=True).start()

if os.environ.get("OFFLINE") == "1":
    threading.Thread(target=offline_watcher, daemon=True).start()

cmd = ["flutter", "test", test, "-d", udid, *extra]
proc = subprocess.Popen(cmd, cwd=APP, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
for line in proc.stdout:
    sys.stdout.write(line)
    sys.stdout.flush()
    if "SHOT:" in line:
        name = line.split("SHOT:", 1)[1].strip()
        path = os.path.join(shots, name + ".png")
        if android:
            png = subprocess.run([ADB, "-s", udid, "exec-out", "screencap", "-p"], capture_output=True).stdout
            open(path, "wb").write(png)
        else:
            subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", path], capture_output=True)
        print(f">>> captured {name}", flush=True)
sys.exit(proc.wait())
