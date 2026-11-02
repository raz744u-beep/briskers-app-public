# Recovered backend module verification

This optional local check uses the private corrected archive already held by
the project owner. It does not download private source or contact a database.
Do not commit that archive, extracted SQL, credentials, or customer data here.

1. Extract `Briskers_Dot_Corrected_Verified_Core_2026-10-29.zip` outside this
   repository. Extract its `original_private_backend.zip` into `original/`.
2. In `original/briskers-private-handoff-20261018/backend`, run
   `npm ci --ignore-scripts --no-audit --no-fund` using the archived lock file.
3. Run `node tools/owner_delete/verify_private_backend.mjs /absolute/extracted/path`.

The script verifies the corrected installer checksum and generated baseline
checksum, then creates a new in-memory PGlite database for each suite. It runs
the corrected SQL modules, exact-signature permission gate, and five archived
synthetic suites. The appointment fixture is marked approved to satisfy the
full baseline's existing validation trigger; no application guard is disabled.

The emulator supplies synthetic Auth sessions and Storage metadata. These
checks do **not** establish real provider object deletion, native Supabase Auth
behavior, concurrency across connections/devices, upgrade compatibility, or
successful execution of the physical-target installer guards. Never use this
module loader as a hosted installer. The archived installer itself is unchanged.

The active sandbox has a newer private-bucket witness check in its storage
inspection function. Preserve that change; do not overwrite hosted functions
with this archived package. A production migration requires a separate,
current-schema review and synthetic hosted acceptance.
