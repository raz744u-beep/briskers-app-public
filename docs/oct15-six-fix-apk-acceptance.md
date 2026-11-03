# October 15 six-fix test build

This branch remains separate from Dot's Delete Job backend work and production deployment.

Acceptance sequence (on owner phone, one by one):
1. Invoice #6345 Work Performed copies typed labor only, preserving entered text.
2. Invoice header is compact and readable at phone width and larger text scale.
3. Add Payment from Jobs and Invoices opens the Payment tab, without auto-entering money.
4. Copy Invoice creates new invoice/new Job; Copy Estimate creates a standalone estimate; both permit same or different saved customer/vehicle, preserve editable notes and item lines, never copy payments.
5. Expense Save stays visible above Android navigation bar and the form scrolls.
6. Owner and Secretary complete jobs independently of payment finalization, and invoice automatically closes only after owner finalization + Job completed + $0 remaining. **Do not test live financial transactions until production backend role guard has been separately approved, deployed and verified.**

Install over current app, never clear data. Protect J-19 and invoice #6346. CI success is not phone acceptance.