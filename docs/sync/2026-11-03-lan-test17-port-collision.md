# Briskers LAN TEST #17 — Port collision regression (Nov 3, 2026)

## Observed Owner screenshot
On launching separate TEST #16, Android displayed:

`Setup failed: SocketException: Failed to create server socket (OS Error: Address already in use, errno = 98), address = 0.0.0.0, port = 48571`.

The QR and Save/Sync controls were disabled because `LanLabTransport.start()` couldn't bind its listener. The pre-existing LAN TEST #15 and #16 were separately installed but **both used the fixed port 48571**, and Android can keep the older app's listener bound even while it is not foregrounded. This is the likely collision, not proof of which process owns it.

## Immediate Owner workaround
On Android Settings -> Apps, **Force stop the older Briskers LAN TEST app** (TEST #15, if present), then reopen TEST #16. Do **not** uninstall or clear data. If the port remains occupied, another app/process may hold it; screenshot + additional diagnostics would be required.

## Code fix
- `LanLabTransport` default preferred listening port is **48572**, separating TEST #17 from #15/#16's 48571.
- On `SocketException` with EADDRINUSE (98) at preferred port, retry binding to port **0** (OS-assigned free port), rather than failing entire initialization.
- Use actual bound port in QR and label. If fallback was required, show a message instructing QR re-pairing if the previous endpoint is now stale. If the OS cannot bind **any** port, show a real setup error.
- Explicit regression test starts a blocker listener occupying the preferred port, asserts the test app binds another port, and transfers an encrypted note with no duplicates.
- Package is now **`com.briskers.lanauto17.briskers_app`** with label `Briskers LAN AUTO TEST 17` so it can install alongside #15/#16 and regular Briskers. It uses separate synthetic-note storage and requires pairing again. Do not claim migration of #15/#16 notes.
- No changes to production customer, invoice, payment, payroll, or Supabase data; this remains a synthetic-only LAN lab.

## Acceptance
1. Keep older TEST #15 app installed and open its listener on 48571.
2. Install TEST #17 and open it; it should show a QR and offer Save Test Note.
3. Pair TEST #17 on two devices, save notes and see automatic exchange without pressing Sync.
4. Restart TEST #17; it should usually retain port 48572 and pairing. If forced onto an OS-assigned fallback port, re-pair if the port differs.
5. Re-run encrypted transfer/dedupe, periodic foreground sync, retry and lifecycle tests before sharing APK.
6. Physical two-device verification still required after CI success.

*This is a test-release fix, not a general production LAN port-management design. Production will require authenticated discovery and device identity for robust re-pairing.*
