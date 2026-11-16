# Payment v2 Android APK build request — October 18, 2026

Source: draft PR #214 head da767ea9f0a11454b09eb86185a7eecee9adfd6d (payment editing); includes UI PR #213 and stabilization PR #209.
Release branch: release/payment-v2-apk-20261018.
Backend v2 migration: approved and successfully deployed on Briskers Dev; SQL migration payment_edit_v2_20261018.
This manifest intentionally triggers the existing permanently signed Android APK build workflow for the isolated release branch. It does not merge any PR or affect customer data.

Acceptance required before user delivery:
- flutter analyze / flutter test pass in APK build run
- permanent Briskers signing certificate SHA-256 verification, not debug certificate
- package com.briskers.briskers_app, versionCode > currently installed version
- artifact verification text and APK source SHA agree with this release commit
- no app uninstall/clear-data on the owner's primary Samsung
- first on-phone checks should remain Force Offline; protect Janet Williams invoice 6348 $175.60 pending local receipt and Sara Mirza invoice 6345
- no live payment finalization, editing, or sync without individual reconciliation and explicit confirmation
