---
name: glaze-native-components-migration
description: |
  Guide for migrating CustomSelect, CustomDropdownMenu, and CustomContextMenu (Radix-based) components to the default native ones (Select, DropdownMenu, ContextMenu). Use this skill when:
  (1) User asks to migrate custom selects, dropdowns, or context menus to native components
  (2) Reviewing code that uses Custom* Select, DropdownMenu, or ContextMenu
  (3) Converting existing UI to use native macOS menus
  (4) Optimizing for native macOS look and feel
---

# Native Components Migration Guide

This guide helps you migrate from Radix UI-based components to their native macOS counterparts (`Select`, `DropdownMenu`, and `ContextMenu`).

## Component Naming History

The component names changed in SDK 0.2.21. The migration patterns below apply regardless of which naming convention the app uses — only the import names differ.

| Component | Before SDK 0.2.21 (legacy) | SDK 0.2.21+ (current) |
| --- | --- | --- |
| Radix select | `Select`, `SelectTrigger`, ... | `CustomSelect`, `CustomSelectTrigger`, ... |
| Native select | `NativeSelect`, `NativeSelectTrigger`, ... | `Select`, `SelectTrigger`, ... |
| Radix dropdown | `DropdownMenu`, `DropdownMenuTrigger`, ... | `CustomDropdownMenu`, `CustomDropdownMenuTrigger`, ... |
| Native dropdown | `NativeDropdownMenu`, `NativeDropdownMenuTrigger`, ... | `DropdownMenu`, `DropdownMenuTrigger`, ... |
| Radix context menu | `ContextMenu`, `ContextMenuTrigger`, ... | `CustomContextMenu`, `CustomContextMenuTrigger`, ... |
| Native context menu | `NativeContextMenu`, `NativeContextMenuTrigger`, ... | `ContextMenu`, `ContextMenuTrigger`, ... |

If the app uses legacy names (`Select`/`NativeSelect`), the SDK upgrade process (Step 3g in the upgrade prompt) handles the rename automatically. The examples below use the current (0.2.21+) naming convention.

## Migration Decision Rules

### Migrate TO Native When

- Items contain **only text** (no custom React components inside)
- Icons can be SF Symbols (strings like `"folder.fill"`) or when not needed
- No custom colors or complex styling on items
- Standard checkmark/checkbox indicators are acceptable

### Keep Custom\* When

- Items contain **custom React children** (components, badges, etc.)
- Need **custom colors** (e.g., `<CircleIcon className="fill-green-9" />` for status)
- Need **multi-line content** in items
- Complex custom styling that native menus don't support

## CustomSelect → Select Migration

### Import Changes

```tsx
// BEFORE
import {
  CustomSelect,
  CustomSelectContent,
  CustomSelectGroup,
  CustomSelectItem,
  CustomSelectLabel,
  CustomSelectSeparator,
  CustomSelectTrigger,
  CustomSelectValue,
} from "@glaze/core/components";

// AFTER
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
} from "@glaze/core/components";
```

### Basic Select Migration

```tsx
// BEFORE
<CustomSelect value={theme} onValueChange={setTheme}>
  <CustomSelectTrigger>
    <CustomSelectValue placeholder="Select theme" />
  </CustomSelectTrigger>
  <CustomSelectContent>
    <CustomSelectItem value="light">Light</CustomSelectItem>
    <CustomSelectItem value="dark">Dark</CustomSelectItem>
    <CustomSelectItem value="system">System</CustomSelectItem>
  </CustomSelectContent>
</CustomSelect>

// AFTER
<Select value={theme} onValueChange={setTheme}>
  <SelectTrigger>
    <SelectValue placeholder="Select theme" />
  </SelectTrigger>
  <SelectContent>
    <SelectItem value="light">Light</SelectItem>
    <SelectItem value="dark">Dark</SelectItem>
    <SelectItem value="system">System</SelectItem>
  </SelectContent>
</Select>
```

### Select with React Icon → Native Select with SF Symbol

```tsx
// BEFORE (React icon component - CANNOT migrate if custom styling needed)
<CustomSelectItem value="grid">
  <GridIcon className="w-4 h-4 mr-2" />
  Grid View
</CustomSelectItem>

// AFTER (SF Symbol icon - simple case)
<SelectItem value="grid" icon="square.grid.2x2">
  Grid View
</SelectItem>
```

### Select with Colored Icons → CANNOT Migrate

```tsx
// CANNOT MIGRATE - uses custom React children with colors
<CustomSelectItem value="active">
  <CircleIcon className="size-3 fill-green-9 text-green-9" />
  Active
</CustomSelectItem>
```

Keep as `CustomSelect` when custom colors are needed.

### Select with Groups

```tsx
// BEFORE
<CustomSelectGroup>
  <CustomSelectLabel>North America</CustomSelectLabel>
  <CustomSelectItem value="est">Eastern (EST)</CustomSelectItem>
  <CustomSelectItem value="pst">Pacific (PST)</CustomSelectItem>
</CustomSelectGroup>

// AFTER
<SelectGroup>
  <SelectLabel>North America</SelectLabel>
  <SelectItem value="est">Eastern (EST)</SelectItem>
  <SelectItem value="pst">Pacific (PST)</SelectItem>
</SelectGroup>
```

## CustomDropdownMenu → DropdownMenu Migration

### Import Changes

```tsx
// BEFORE
import {
  CustomDropdownMenu,
  CustomDropdownMenuContent,
  CustomDropdownMenuItem,
  CustomDropdownMenuCheckboxItem,
  CustomDropdownMenuSeparator,
  CustomDropdownMenuLabel,
  CustomDropdownMenuSub,
  CustomDropdownMenuSubTrigger,
  CustomDropdownMenuSubContent,
  CustomDropdownMenuTrigger,
} from "@glaze/core/components";

// AFTER
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuCheckboxItem,
  DropdownMenuSeparator,
  DropdownMenuLabel,
  DropdownMenuSub,
  DropdownMenuTrigger,
} from "@glaze/core/components";
```

### Basic Menu Migration

```tsx
// BEFORE
<CustomDropdownMenu>
  <CustomDropdownMenuTrigger asChild>
    <Button iconOnly variant="glass">
      <MoreHorizontalIcon className="w-4 h-4" />
    </Button>
  </CustomDropdownMenuTrigger>
  <CustomDropdownMenuContent>
    <CustomDropdownMenuItem onSelect={handleEdit}>
      <EditIcon className="w-4 h-4" />
      Edit
    </CustomDropdownMenuItem>
    <CustomDropdownMenuItem onSelect={handleDelete}>
      <TrashIcon className="w-4 h-4" />
      Delete
    </CustomDropdownMenuItem>
  </CustomDropdownMenuContent>
</CustomDropdownMenu>

// AFTER
<DropdownMenu>
  <DropdownMenuTrigger asChild>
    <Button iconOnly variant="glass">
      <MoreHorizontalIcon className="w-4 h-4" />
    </Button>
  </DropdownMenuTrigger>
  <DropdownMenuContent>
    <DropdownMenuItem icon="pencil" onSelect={handleEdit}>
      Edit
    </DropdownMenuItem>
    <DropdownMenuItem icon="trash" onSelect={handleDelete}>
      Delete
    </DropdownMenuItem>
  </DropdownMenuContent>
</DropdownMenu>
```

### Checkbox Items Migration

```tsx
// BEFORE
<CustomDropdownMenuCheckboxItem
  checked={showHidden}
  onCheckedChange={setShowHidden}
>
  Show Hidden Files
</CustomDropdownMenuCheckboxItem>

// AFTER
<DropdownMenuCheckboxItem
  checked={showHidden}
  onCheckedChange={setShowHidden}
>
  Show Hidden Files
</DropdownMenuCheckboxItem>
```

### Submenu Migration

```tsx
// BEFORE
<CustomDropdownMenuSub>
  <CustomDropdownMenuSubTrigger>
    <ShareIcon className="w-4 h-4" />
    Share
  </CustomDropdownMenuSubTrigger>
  <CustomDropdownMenuSubContent>
    <CustomDropdownMenuItem onSelect={handleEmail}>Email</CustomDropdownMenuItem>
    <CustomDropdownMenuItem onSelect={handleCopy}>Copy Link</CustomDropdownMenuItem>
  </CustomDropdownMenuSubContent>
</CustomDropdownMenuSub>

// AFTER
<DropdownMenuSub label="Share" icon="square.and.arrow.up">
  <DropdownMenuItem icon="envelope" onSelect={handleEmail}>
    Email
  </DropdownMenuItem>
  <DropdownMenuItem icon="doc.on.clipboard" onSelect={handleCopy}>
    Copy Link
  </DropdownMenuItem>
</DropdownMenuSub>
```

### Keyboard Shortcut Display → Native Accelerator

```tsx
// BEFORE (styled shortcut component)
<CustomDropdownMenuItem>
  Copy
  <CustomDropdownMenuShortcut>⌘C</CustomDropdownMenuShortcut>
</CustomDropdownMenuItem>

// AFTER (native accelerator - displays slightly differently)
<DropdownMenuItem accelerator="⌘C" onSelect={handleCopy}>
  Copy
</DropdownMenuItem>
```

## CustomContextMenu → ContextMenu Migration

### Import Changes

```tsx
// BEFORE
import {
  CustomContextMenu,
  CustomContextMenuContent,
  CustomContextMenuItem,
  CustomContextMenuCheckboxItem,
  CustomContextMenuSeparator,
  CustomContextMenuLabel,
  CustomContextMenuSub,
  CustomContextMenuSubTrigger,
  CustomContextMenuSubContent,
  CustomContextMenuTrigger,
  CustomContextMenuShortcut,
} from "@glaze/core/components";

// AFTER
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuCheckboxItem,
  ContextMenuSeparator,
  ContextMenuLabel,
  ContextMenuSub,
  ContextMenuTrigger,
} from "@glaze/core/components";
```

### Basic Context Menu Migration

```tsx
// BEFORE
<CustomContextMenu>
  <CustomContextMenuTrigger asChild>
    <div>Right-click me</div>
  </CustomContextMenuTrigger>
  <CustomContextMenuContent>
    <CustomContextMenuItem onClick={handleEdit}>
      <PencilIcon className="w-4 h-4" />
      Edit
    </CustomContextMenuItem>
    <CustomContextMenuItem onClick={handleDelete}>
      <TrashIcon className="w-4 h-4" />
      Delete
    </CustomContextMenuItem>
  </CustomContextMenuContent>
</CustomContextMenu>

// AFTER
<ContextMenu>
  <ContextMenuTrigger asChild>
    <div>Right-click me</div>
  </ContextMenuTrigger>
  <ContextMenuContent>
    <ContextMenuItem icon="pencil" onSelect={handleEdit}>
      Edit
    </ContextMenuItem>
    <ContextMenuItem icon="trash" onSelect={handleDelete}>
      Delete
    </ContextMenuItem>
  </ContextMenuContent>
</ContextMenu>
```

### Context Menu Checkbox Items

```tsx
// BEFORE
<CustomContextMenuCheckboxItem
  checked={showHidden}
  onCheckedChange={setShowHidden}
>
  Show Hidden Files
</CustomContextMenuCheckboxItem>

// AFTER
<ContextMenuCheckboxItem
  checked={showHidden}
  onCheckedChange={setShowHidden}
>
  Show Hidden Files
</ContextMenuCheckboxItem>
```

### Context Menu Submenu Migration

```tsx
// BEFORE
<CustomContextMenuSub>
  <CustomContextMenuSubTrigger>
    <ShareIcon className="w-4 h-4" />
    Share
  </CustomContextMenuSubTrigger>
  <CustomContextMenuSubContent>
    <CustomContextMenuItem onClick={handleEmail}>Email</CustomContextMenuItem>
    <CustomContextMenuItem onClick={handleCopy}>Copy Link</CustomContextMenuItem>
  </CustomContextMenuSubContent>
</CustomContextMenuSub>

// AFTER
<ContextMenuSub label="Share" icon="square.and.arrow.up">
  <ContextMenuItem icon="envelope" onSelect={handleEmail}>
    Email
  </ContextMenuItem>
  <ContextMenuItem icon="doc.on.clipboard" onSelect={handleCopy}>
    Copy Link
  </ContextMenuItem>
</ContextMenuSub>
```

### Context Menu Keyboard Shortcuts → Accelerator

```tsx
// BEFORE
<CustomContextMenuItem onClick={handleCopy}>
  Copy
  <CustomContextMenuShortcut>⌘C</CustomContextMenuShortcut>
</CustomContextMenuItem>

// AFTER
<ContextMenuItem accelerator="⌘C" onSelect={handleCopy}>
  Copy
</ContextMenuItem>
```

### Key Differences: CustomContextMenu vs ContextMenu

| Feature               | CustomContextMenu (Radix)       | ContextMenu        |
| --------------------- | ------------------------------- | ------------------ |
| Custom React children | Yes, full support               | No, text only      |
| Custom item colors    | Yes, via className              | Not supported      |
| Radio groups          | Yes, supported                  | Not supported      |
| SF Symbol icons       | No, need React components       | Yes, `icon` prop   |
| Native appearance     | No, custom styled               | Yes, macOS native  |
| Keyboard accelerators | Via `CustomContextMenuShortcut` | `accelerator` prop |

## Common SF Symbol Mappings

When migrating React icons to SF Symbols:

| React Icon Pattern                 | SF Symbol                     |
| ---------------------------------- | ----------------------------- |
| `<EditIcon />`, `<PencilIcon />`   | `"pencil"`                    |
| `<TrashIcon />`, `<Trash2Icon />`  | `"trash"` or `"trash.fill"`   |
| `<CopyIcon />`                     | `"doc.on.doc"`                |
| `<ShareIcon />`                    | `"square.and.arrow.up"`       |
| `<FolderIcon />`                   | `"folder"` or `"folder.fill"` |
| `<FileIcon />`, `<DocumentIcon />` | `"doc"` or `"doc.fill"`       |
| `<SettingsIcon />`, `<GearIcon />` | `"gear"`                      |
| `<StarIcon />`                     | `"star"` or `"star.fill"`     |
| `<EyeIcon />`                      | `"eye"`                       |
| `<EyeOffIcon />`                   | `"eye.slash"`                 |
| `<DownloadIcon />`                 | `"arrow.down.circle"`         |
| `<UploadIcon />`                   | `"arrow.up.circle"`           |
| `<RefreshIcon />`                  | `"arrow.clockwise"`           |
| `<SearchIcon />`                   | `"magnifyingglass"`           |
| `<PlusIcon />`                     | `"plus"`                      |
| `<CheckIcon />`                    | `"checkmark"`                 |
| `<XIcon />`, `<CloseIcon />`       | `"xmark"`                     |
| `<GridIcon />`                     | `"square.grid.2x2"`           |
| `<ListIcon />`                     | `"list.bullet"`               |
| `<InfoIcon />`                     | `"info.circle"`               |
| `<AlertIcon />`, `<WarningIcon />` | `"exclamationmark.triangle"`  |
| `<LinkIcon />`                     | `"link"`                      |
| `<ExternalLinkIcon />`             | `"arrow.up.forward.square"`   |
| `<PlayIcon />`                     | `"play.fill"`                 |
| `<PauseIcon />`                    | `"pause.fill"`                |
| `<StopIcon />`                     | `"stop.fill"`                 |

The `icon` prop has full TypeScript autocomplete for all SF Symbols.

## Migration Checklist

When migrating a component:

1. [ ] Check if any items have custom React children (badges, styled icons)
2. [ ] Check if any items have custom colors
3. [ ] Check if radio groups are used (only `CustomContextMenu` supports these)
4. [ ] Update imports
5. [ ] Replace component names (remove `Custom` prefix)
6. [ ] Convert React icon components to SF Symbol strings (or PNG icons)
7. [ ] For submenus, move label to prop: `label="Share"` instead of children
8. [ ] Convert `onClick` to `onSelect` for menu items
9. [ ] Convert `CustomContextMenuShortcut`/`CustomDropdownMenuShortcut` to `accelerator` prop
10. [ ] Test that all functionality works with native menu
