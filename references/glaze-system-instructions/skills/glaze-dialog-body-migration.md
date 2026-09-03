---
name: glaze-dialog-body-migration
description: Migrate Dialog and AlertDialog components to the new padding architecture where DialogBody handles horizontal padding and scrolling instead of DialogContent.
---

# Glaze Dialog Body Migration

This is a **one-time migration** for apps upgrading to SDK 0.2.10+. Starting with this version, `DialogContent` and `AlertDialogContent` no longer apply horizontal padding. Instead, each sub-component (`DialogHeader`, `DialogBody`, `DialogFooter`) handles its own horizontal padding via the `--dialog-px` CSS variable.

## What Changed

- `DialogContent` padding changed from `p-6` to `py-6` — horizontal padding was removed.
- New `DialogBody` component wraps content in a `ScrollArea` with faded edges, providing automatic scrollability when content overflows.
- `DialogHeader` and `DialogFooter` now apply their own horizontal padding via `--dialog-px`.
- Any direct children of `DialogContent` that aren't `DialogHeader`, `DialogBody`, or `DialogFooter` must add `px-(--dialog-px)` manually.
- The same applies to `AlertDialogContent` with `AlertDialogBody`.

## Migration Steps

### 1. Update Dialog imports

Add `DialogBody` to existing dialog imports from `@glaze/core/components`:

```tsx
// Before
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
  DialogClose,
} from "@glaze/core/components";

// After
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
  DialogClose,
} from "@glaze/core/components";
```

For AlertDialog, add `AlertDialogBody`:

```tsx
import { AlertDialog, AlertDialogBody, AlertDialogContent, AlertDialogHeader, ... } from "@glaze/core/components";
```

### 2. Wrap dialog body content in DialogBody

Any content between `DialogHeader` and `DialogFooter` should be wrapped in `<DialogBody>`:

```tsx
// Before
<DialogContent>
  <DialogHeader>...</DialogHeader>
  <div className="flex flex-col gap-4">
    <Input ... />
    <Textarea ... />
  </div>
  <DialogFooter>...</DialogFooter>
</DialogContent>

// After
<DialogContent>
  <DialogHeader>...</DialogHeader>
  <DialogBody className="flex flex-col gap-4">
    <Input ... />
    <Textarea ... />
  </DialogBody>
  <DialogFooter>...</DialogFooter>
</DialogContent>
```

### 3. Move layout classes to DialogBody

If there's a wrapper `<div>` around body content with layout classes (e.g., `className="flex flex-col gap-4"` or `className="space-y-4"`), move those classes to `DialogBody`'s `className` and remove the wrapper div:

```tsx
// Before
<div className="flex flex-col gap-4">
  <Input ... />
  <Textarea ... />
</div>

// After
<DialogBody className="flex flex-col gap-4">
  <Input ... />
  <Textarea ... />
</DialogBody>
```

### 4. Handle standalone direct children of DialogContent

Any direct children of `DialogContent` that are NOT `DialogHeader`, `DialogBody`, or `DialogFooter` (e.g., icon divs, decorative elements, loading spinners) must add horizontal padding manually:

```tsx
// Before (worked when DialogContent had p-6)
<DialogContent>
  <div className="flex justify-center">
    <Spinner />
  </div>
</DialogContent>

// After
<DialogContent>
  <div className="flex justify-center px-(--dialog-px)">
    <Spinner />
  </div>
</DialogContent>
```

### 5. Apply the same changes to AlertDialog

`AlertDialogBody` works identically to `DialogBody`. Apply the same migration pattern:

```tsx
<AlertDialogContent>
  <AlertDialogHeader>...</AlertDialogHeader>
  <AlertDialogBody className="space-y-4">{/* body content */}</AlertDialogBody>
  <AlertDialogFooter>...</AlertDialogFooter>
</AlertDialogContent>
```

### 6. Build and verify

```bash
glaze build
```

Fix any errors and rebuild until clean. Visually verify that dialogs have correct horizontal padding.

## Important Notes

- Dialogs that only have `DialogHeader` and `DialogFooter` (no body content) need no changes — the header and footer handle their own padding.
- `DialogBody` uses `max-h-[50vh]` by default. Override with `scrollAreaClassName="max-h-[30vh]"` if the dialog header/footer are particularly tall.
- Do not add `px-6` or other manual horizontal padding to `DialogHeader`, `DialogFooter`, or `DialogBody` — they already use `--dialog-px`.
