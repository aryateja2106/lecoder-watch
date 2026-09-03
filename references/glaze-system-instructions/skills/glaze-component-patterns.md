---
name: Glaze Component Patterns
description: Patterns and best practices for building native macOS-style layouts using Glaze's design system components.
---

# Glaze Component Patterns

This skill guides you in building native macOS interfaces using Glaze's design system components.

## Design System Components

The `@glaze/core` package provides a complete design system. Components handle native macOS styling automatically. Documentation (`.md` files) and source (`.tsx` files) are in `../../../sdk/current/@glaze/core/src/components/` (relative to `.glaze-sources/`).

### Import Structure

Components, hooks, and utilities are organized into separate entry points:

```typescript
// UI Components
import { Button, Dialog, Sidebar, Panel } from "@glaze/core/components";

// React Hooks
import { useTheme, useConnection, useEnvironment } from "@glaze/core/hooks";

// Utilities (no React dependency)
import { cn, initLogging, isDevelopmentFlavor } from "@glaze/core/utils";
```

### Component Reference

**NEVER create custom implementations for these patterns.** Always use the design system components:

| Pattern | Component | Docs | Import |
| --- | --- | --- | --- |
| **Layout** |  |  |  |
| Resizable panels | `PanelGroup`, `Panel` | `panel.md` | `import { PanelGroup, Panel } from "@glaze/core/components"` |
| Application sidebar | `Sidebar`, `SidebarList`, `SidebarListItem`, `SidebarListGroup`, `SidebarFooter`, `SidebarListItemContent`, `SidebarListItemTitle`, `SidebarListItemSubtitle`, `SidebarListItemAccessory` | `sidebar.md` | `import { Sidebar, SidebarList, SidebarListItem, SidebarListGroup, SidebarFooter } from "@glaze/core/components"` |
| Sidebar search | `Sidebar` with `searchable` prop | `sidebar.md` | Search is built into `Sidebar` — use `searchable` prop instead of manual `ToolbarSearchInput` |
| Top/bottom toolbar | `Toolbar`, `ToolbarRow`, `ToolbarActions`, `ToolbarContent`, `ToolbarTitle`, `ToolbarDescription` | `toolbar.md` | `import { Toolbar, ToolbarRow, ToolbarActions, ToolbarContent, ToolbarTitle, ToolbarDescription } from "@glaze/core/components"` |
| Toolbar search | `ToolbarSearchButton` | `toolbar.md` | `import { ToolbarSearchButton } from "@glaze/core/components"` |
| Scrollable container | `ScrollArea` | `scroll-area.md` | `import { ScrollArea } from "@glaze/core/components"` |
| Grid with keyboard nav | `Grid.Root`, `Grid.Item` | `grid.md` | `import * as Grid from "@glaze/core/components"` |
| Vertical list with selection | `List.Root`, `List.Item`, `List.ItemTitle` | `list.md` | `import * as List from "@glaze/core/components"` |
| Disclosure / expandable section | `CollapsibleRoot`, `CollapsibleTrigger`, `CollapsibleContent`, `CollapsibleChevron` | `collapsible.md` | `import { CollapsibleRoot, CollapsibleTrigger, CollapsibleContent, CollapsibleChevron } from "@glaze/core/components"` |
| Visual divider | `Separator` | - | `import { Separator } from "@glaze/core/components"` |
| **Forms** |  |  |  |
| Text input | `Input` | - | `import { Input } from "@glaze/core/components"` |
| Multi-line text | `Textarea` | `textarea.md` | `import { Textarea } from "@glaze/core/components"` |
| Dropdown select | `Select`, `SelectTrigger`, `SelectContent`, `SelectItem` | `select.md` | `import { Select, SelectTrigger, SelectContent, SelectItem, SelectValue } from "@glaze/core/components"` |
| Dropdown select (custom, advanced) | `CustomSelect`, `CustomSelectTrigger`, `CustomSelectContent`, `CustomSelectItem` | `custom-select.md` | `import { CustomSelect, CustomSelectTrigger, CustomSelectContent, CustomSelectItem, CustomSelectValue } from "@glaze/core/components"` |
| Boolean toggle (checkbox) | `Checkbox` | `checkbox.md` | `import { Checkbox } from "@glaze/core/components"` |
| Boolean toggle (switch) | `Switch` | `switch.md` | `import { Switch } from "@glaze/core/components"` |
| Radio button group | `RadioGroup`, `RadioGroupItem` | `radio-group.md` | `import { RadioGroup, RadioGroupItem } from "@glaze/core/components"` |
| Range slider | `Slider` | `slider.md` | `import { Slider } from "@glaze/core/components"` |
| Form field wrapper | `FieldSet`, `Field` (with `label` / `description` / `error` sugar) | `field.md` | `import { FieldSet, Field } from "@glaze/core/components"` |
| Form label | `Label` | - | `import { Label } from "@glaze/core/components"` |
| **Actions** |  |  |  |
| Clickable button | `Button` | `button.md` | `import { Button } from "@glaze/core/components"` |
| Grouped buttons | `ButtonGroup`, `ButtonGroupSeparator` | `button-group.md` | `import { ButtonGroup, ButtonGroupSeparator } from "@glaze/core/components"` |
| Back/forward navigation | `NavigationButtonGroup` | `button-group.md` | `import { NavigationButtonGroup } from "@glaze/core/components"` |
| Dropdown menu | `DropdownMenu`, `DropdownMenuTrigger`, `DropdownMenuContent`, `DropdownMenuItem` | `dropdown-menu.md` | `import { DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem } from "@glaze/core/components"` |
| Dropdown menu (custom, advanced) | `CustomDropdownMenu`, `CustomDropdownMenuTrigger`, `CustomDropdownMenuContent`, `CustomDropdownMenuItem` | `custom-dropdown-menu.md` | `import { CustomDropdownMenu, CustomDropdownMenuTrigger, CustomDropdownMenuContent, CustomDropdownMenuItem } from "@glaze/core/components"` |
| Command palette | `Command`, `CommandDialog`, `CommandInput`, `CommandList`, `CommandItem` | `command.md` | `import { Command, CommandDialog, CommandInput, CommandList, CommandItem } from "@glaze/core/components"` |
| Right-click menu | `ContextMenu`, `ContextMenuTrigger`, `ContextMenuContent`, `ContextMenuItem` | `context-menu.md` | `import { ContextMenu, ContextMenuTrigger, ContextMenuContent, ContextMenuItem } from "@glaze/core/components"` |
| Right-click menu (custom, advanced) | `CustomContextMenu`, `CustomContextMenuTrigger`, `CustomContextMenuContent`, `CustomContextMenuItem` | `custom-context-menu.md` | `import { CustomContextMenu, CustomContextMenuTrigger, CustomContextMenuContent, CustomContextMenuItem } from "@glaze/core/components"` |
| **Dialogs & Overlays** |  |  |  |
| Modal dialog | `Dialog` (with `trigger` / `title` / `description` / `onConfirm` sugar) | `dialog.md` | `import { Dialog } from "@glaze/core/components"` |
| Dialog primitives (escape hatch) | `DialogContent`, `DialogHeader`, `DialogTitle`, `DialogDescription`, `DialogBody`, `DialogFooter`, `DialogTrigger`, `DialogClose` | `dialog.md` | `import { DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogBody, DialogFooter, DialogTrigger, DialogClose } from "@glaze/core/components"` |
| Alert (must-decide) dialog | `AlertDialog` (with `trigger` / `title` / `description` / `onConfirm` sugar) | `alert-dialog.md` | `import { AlertDialog } from "@glaze/core/components"` |
| Hover tooltip | `Tooltip`, `TooltipTrigger`, `TooltipContent`, `TooltipProvider` | `tooltip.md` | `import { Tooltip, TooltipTrigger, TooltipContent, TooltipProvider } from "@glaze/core/components"` |
| **Feedback** |  |  |  |
| Toast notifications | `Toaster` + `toast()` | `sonner.md` | `import { Toaster, toast } from "@glaze/core/components"` |
| Status badge | `Status` | - | `import { Status } from "@glaze/core/components"` |
| Empty content placeholder | `EmptyState`, `EmptyStateTitle`, `EmptyStateDescription`, `EmptyStateActions`, `EmptyStateMedia` | `empty-state.md` | `import { EmptyState, EmptyStateTitle, EmptyStateDescription, EmptyStateActions, EmptyStateMedia } from "@glaze/core/components"` |
| Edge blur effect | `ProgressiveBlur` | - | `import { ProgressiveBlur } from "@glaze/core/components"` |
| **Data Display** |  |  |  |
| Data table | `Table`, `TableHeader`, `TableBody`, `TableRow`, `TableCell` | `table.md` | `import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from "@glaze/core/components"` |
| Segmented controls | `TabsRoot`, `Tabs`, `TabsTrigger`, `TabsSeparator`, `TabsContent` | `tabs.md` | `import { TabsRoot, Tabs, TabsTrigger, TabsSeparator, TabsContent } from "@glaze/core/components"` |

### Hooks Reference

| Hook                  | Purpose                        | Import                                                    |
| --------------------- | ------------------------------ | --------------------------------------------------------- |
| `useTheme`            | Apply theme styles to document | `import { useTheme } from "@glaze/core/hooks"`            |
| `useConnection`       | IPC connection status          | `import { useConnection } from "@glaze/core/hooks"`       |
| `useEnvironment`      | App environment info           | `import { useEnvironment } from "@glaze/core/hooks"`      |
| `useWindowFocusState` | Window focus tracking          | `import { useWindowFocusState } from "@glaze/core/hooks"` |

### Utils Reference

| Utility               | Purpose                    | Import                                                    |
| --------------------- | -------------------------- | --------------------------------------------------------- |
| `cn`                  | Merge Tailwind classes     | `import { cn } from "@glaze/core/utils"`                  |
| `initLogging`         | Initialize console logging | `import { initLogging } from "@glaze/core/utils"`         |
| `isDevelopmentFlavor` | Check if dev build         | `import { isDevelopmentFlavor } from "@glaze/core/utils"` |

## MANDATORY: Read Component Documentation First

**CRITICAL: You MUST read the `.md` documentation file for EVERY component before using it.**

Component documentation and source files are in the shared SDK:

| Resource | Location | Example |
| --- | --- | --- |
| **Documentation** | `../../../sdk/current/@glaze/core/src/components/<component>.md` | `../../../sdk/current/@glaze/core/src/components/sidebar.md` |
| **Source** | `../../../sdk/current/@glaze/core/src/components/<component>.tsx` | `../../../sdk/current/@glaze/core/src/components/sidebar.tsx` |

Each `.md` file documents:

- Available props and their types
- Variants and sizes
- Composition patterns
- Keyboard navigation behavior
- Common pitfalls to avoid

**Before writing any code:**

1. Identify ALL components needed for your implementation
2. **READ the `.md` file for EACH component** - this is not optional
3. Only then start implementing

**Why this matters:** Components handle window dragging, native styling, keyboard navigation, and accessibility. Skipping the docs leads to broken macOS behavior, missed features, and incorrect usage patterns.

```
Task: "Build notes app with sidebar"
❌ DON'T: Start coding immediately
❌ DON'T: Guess at component props or structure
✅ DO: Read ../../../sdk/current/@glaze/core/src/components/ docs: sidebar.md, panel.md, toolbar.md, list.md
✅ DO: Then implement using documented patterns
```

---

## Standard Layout Pattern

Most Glaze apps follow a **sidebar + content** layout using `PanelGroup` and `Panel`.

**Before implementing any layout, read these component docs:**

1. `panel.md` - Two-panel and three-panel layout patterns, size guidelines, collapsible panels
2. `sidebar.md` - Sidebar structure, toolbar placement, `SidebarList` usage
3. `toolbar.md` - Toolbar composition, button variants per context

**Key points:**

- First panel(s): Set `defaultSize` and `minSize`
- Last panel: No `defaultSize` (fills remaining space)
- Every panel needs a `Toolbar` for window dragging
- **Sidebar**: Use `searchable` and `actions` convenience props — buttons are auto-styled (`variant="transparent" size="small"`). Only use the `toolbar` escape hatch for custom layouts (tabs, segmented controls).
- **SidebarListItem**: Prefer the props API — `icon`, `title`, `subtitle`, `accessory`. Only use children mode when the structural layout differs (e.g. top-aligned accessory). Use `collapsible` + `forceOpen` for expandable rows.
- **SidebarListGroup**: Use the `title` prop for section headers. Use `collapsible` for Apple Mail-style sections with hover-revealed chevron + actions.
- **SidebarList**: Use `items`, `selectedItem`, `onSelectedItemChange`, `getItemKey` for managed selection. Use `item` prop on each `SidebarListItem`. Only use manual `selected`/`onClick` for route-based navigation.
- Content toolbar buttons: `variant="glass"`
- `ToolbarTitle` is optional: use it only when users need context (active tab/file/section). For simple single-view apps, omit it. Avoid app-name titles unless explicitly requested.

---

## FORBIDDEN: Raw HTML Elements

**NEVER use raw HTML elements when a design system component exists in `@glaze/core/components`.**

| FORBIDDEN | USE INSTEAD |
| --- | --- |
| `<button>` | `Button` |
| `<input>` | `Input` |
| `<input type="checkbox">` | `Checkbox` |
| `<input type="radio">` | `RadioGroup`, `RadioGroupItem` |
| `<select>` | `Select` or `CustomSelect` for custom children |
| `<textarea>` | `Textarea` |
| `<table>`, `<tr>`, `<td>` | `Table`, `TableHeader`, `TableBody`, `TableRow`, `TableCell` |
| `<dialog>` | `Dialog` (with sugar: `trigger`, `title`, `description`, `onConfirm`) |
| `<ul>/<li>` for interactive lists | `List.Root`, `List.Item` |
| `<nav>` for sidebar | `Sidebar`, `SidebarList`, `SidebarListItem` |
| `<label>` | `Label` |
| `<fieldset>` | `Field`, `FieldLabel`, `FieldContent` |
| `<input type="range">` | `Slider` |
| Custom toggle/switch | `Switch` |
| Custom tabs | `TabsRoot`, `Tabs`, `TabsTrigger`, `TabsContent` |
| Custom dropdown | `DropdownMenu` or `CustomDropdownMenu` for custom children/styling |
| Custom tooltip | `Tooltip`, `TooltipTrigger`, `TooltipContent` |
| Custom toast/notification | `Toaster` + `toast()` from `@glaze/core/components` |
| Custom modal | `Dialog` (or `AlertDialog` for must-decide confirmations) |
| Custom command palette | `Command`, `CommandDialog`, `CommandInput`, `CommandList`, `CommandItem` |
| Custom context menu | `ContextMenu` or `CustomContextMenu` for custom children/styling |
| Custom scrollable container | `ScrollArea` |
| Custom accordion / expandable row | `CollapsibleRoot`, `CollapsibleTrigger`, `CollapsibleContent`, `CollapsibleChevron` |
| Custom resizable panels | `PanelGroup`, `Panel` |
| Custom grid layout | `Grid.Root`, `Grid.Item` |
| Custom empty state | `EmptyState`, `EmptyStateTitle`, `EmptyStateDescription` |
| Custom status indicator | `Status` |
| Custom button group | `ButtonGroup`, `ButtonGroupSeparator` |

---

## Core Rules

1. **Every panel needs a Toolbar** - Without it, users can't drag the window
2. **Use design system components** - Never use custom `<div>` replacements
3. **Sidebar convenience props** - Use `searchable`, `actions` props on `Sidebar` instead of manual `toolbar` composition. Buttons in `actions` are auto-styled (`variant="transparent" size="small"`, icons `size-4`). Only use the `toolbar` prop escape hatch for custom layouts (tabs, segmented controls).
4. **SidebarList managed selection** - Use `items`, `selectedItem`, `onSelectedItemChange`, `getItemKey` on `SidebarList` and `item` prop on `SidebarListItem`. Only use manual `selected`/`onClick` for route-based navigation.
5. **Content toolbars = contextual title + actions** - `ToolbarContent` + `ToolbarActions`
6. **Content toolbar button variants and sizing**:
   - Content area toolbars: `<Button variant="glass" size="large">` — icons `size-4.5` (18px)
   - `ButtonGroup` controls child button sizing — do NOT set `size` on buttons inside a `ButtonGroup`
   - `NavigationButtonGroup`: defaults to `size="large"` `variant="glass"` — in sidebars pass `size="small" variant="transparent"`
   - Content area: `ToolbarSearchButton size="large"`, `Tabs size="large"`
7. **Use `ToolbarTitle` only when context is needed** - For simple single-view apps, omit it. If used, prefer section/document context; use app name only when explicitly requested.

8. **One accent button per screen/dialog** - The `variant="accent"` button is the primary action. All other buttons use `variant="filled"` or `variant="transparent"`. Never have two accent buttons visible at the same time.
9. **Dialogs — use the sugar by default, drop to primitives only for custom footers or wizards:**
   - Write `<Dialog trigger={<Button>Open</Button>} title="..." description="..." onConfirm={async () => { await save(); }}>{body}</Dialog>`. The sugar auto-builds the trigger, header, body (children), and footer (Cancel + Confirm), manages open state, and disables the confirm button while `onConfirm` is in flight. On throw the dialog stays open so the caller can surface the error — wrap async work in `try { await save() } catch (err) { toast.error(...); throw err; }` to show a toast AND keep the dialog open for retry. The sugar deliberately does **not** render an inline spinner inside the button (would jitter the width).
   - **`Dialog` vs `AlertDialog`:** the deciding question is _"if the user accidentally hits Esc, is that a safe no-op?"_ If yes → `Dialog` (forms, edit sheets, info modals, "What's New"). If no → `AlertDialog` (delete, unpublish, remove, sign-out, leave-with-unsaved). Destructiveness alone isn't the test — "unsaved changes, leave anyway?" is an `AlertDialog` even though the confirm is `accent`, not red.
   - **AlertDialog's `confirmVariant`:** `"destructive"` for irreversible destructive actions (delete, unpublish, remove member, reset API key). `"accent"` (default) for non-destructive confirmations (leave unsaved, sign out, publish). Name the action in `confirmLabel` — "Delete", "Leave", "Sign Out", "Unpublish" — not "OK" or "Confirm".
   - **Write specific descriptions.** "8 people have this installed" beats "Are you sure?". Spell out the downstream consequences so the user can make an informed choice.
   - **Multi-action form sheets (rare):** `Dialog` with `destructiveAction` — left-aligned side button for an escape hatch (e.g. "Edit Member" with a "Remove from Organization" destructive side action). The destructive side button is styled `filled`, not red — red is reserved for the follow-up `AlertDialog` that _commits_ the destructive action. `secondaryAction` is also available but with both set you get 4 buttons that stack vertically; usually a sign to rethink the UX.
   - Drop to primitives (`DialogContent`, `DialogHeader`, `DialogFooter`, ...) **only** when the _footer itself_ needs extra content (e.g. a "Don't show again" checkbox, inline progress, a validation banner), multi-step wizards (Back/Next/Finish), two equally-primary buttons (Save as Draft + Publish), bulleted consequence lists inside an alert, or forms whose submit lives inside a `<form>` for native Enter-to-submit. **Body-only customization (pre-formatted output, code blocks, diffs, custom layouts) stays in sugar** — just pass it as `children`. **Form validation / typed-name-to-confirm stays in sugar** — use `confirmDisabled={...}`.
   - **Don't mix sugar and primitives.** If you set `title` / `description` / `onConfirm`, don't also pass `<DialogHeader>` / `<DialogFooter>` as children — children are treated as body content in sugar mode.
   - **All text-ish sugar props (`title`, `description`, `confirmLabel`, `trigger`, side-action `label`) are `ReactNode`.** Pass inline icons, fragments, `<code>`, etc. without escaping to primitives — e.g. `confirmLabel={<><TrashIcon className="size-4" /> Delete</>}`.
10. **Settings / form rows — use the Field sugar, never sausage buttons:**
    - Write `<FieldSet title="Section"><Field label="Row" description="...">{control}</Field></FieldSet>`. The sugar builds `FieldContent` + `FieldLabel` + `FieldDescription` + `FieldGroup` + `FieldLegend` automatically, and lays the row out horizontally (label left, control right) — the native macOS settings convention.
    - **Never wrap a `<Button>` in `<Field orientation="vertical">` without realizing it makes it full-width.** The vertical orientation stretches children; buttons become "sausage buttons" (wide, ugly, wrong). The default horizontal orientation in sugar mode never does this — buttons render at intrinsic width.
    - For a row that is **just an action button** (Save / Apply / Reset), use `<Field><Button>...</Button></Field>` without a label — the button renders at intrinsic width, right-aligned. Multiple buttons in one Field wrap cleanly.
    - **Short single-line text** (display name, alias, email) → inline `<Input>` in a `<Field>`; commit on blur, no Save button. **Multi-line text / long-form content** (custom instructions, bios, signatures, prompts, release notes) → **always open in a Dialog**, never inline a `<Textarea>` in a settings row. Inline textareas break the row grid, feel cramped, and blow up at certain content lengths. Use `<Dialog trigger={<Field label description disabled={loading}><ChevronRightIcon className="size-4 shrink-0 text-gray-a9" /></Field>}>` + a sized `<Textarea>` inside. The whole row becomes a disclosure (chevron + press to edit).
    - **Keep label + description static across control states.** Do NOT conditionally remove the description when a toggle flips on, or swap it for different text mid-render. Showing/hiding text between states causes layout shift (CLS) and makes the row visually twitch. If the copy needs to hint at enabled/disabled state, pick wording that reads right in both ("Included in every AI request") and leave it alone. If state genuinely changes a _value_ (not a description), put the value in the control slot on the right — not by rewriting the description.
    - Use `orientation="vertical"` **only** when the control is large and should sit below the label (e.g. image pickers, in-dialog form fields). In settings rows, prefer the Dialog pattern above over `orientation="vertical"`+Textarea.

### Dark Mode

Radix color scales handle most light/dark switching automatically. The main thing to watch for with custom styling:

- Use Radix scale tokens (`gray-1` through `gray-12`, `gray-a1` through `gray-a12`) instead of hardcoded `white`/`black` — the scales resolve correctly per theme
- Alpha tokens (`border-gray-a4`, `text-gray-a11`) are your friend — they adapt to both modes without `dark:` overrides
- Radix scales are designed so adjacent steps (`gray-1` → `gray-2` → `gray-3`) are subtle enough for nesting — use `gray-2` for a recessed well on a `gray-1` page, not `gray-4` which jumps too far and looks like a separate element

---

## Required Component Usage

- Sidebars → `Sidebar` (not ScrollArea with custom divs)
- Lists → `List.Root` + `List.Item` (not custom divs with onClick)
- Scrollable panels → `ScrollArea` with `toolbar` prop
- **EVERY panel needs a `Toolbar`** for window dragging

---

## Sticky Positioning & Scroll Containers

- **Single scroll container rule:** Only ONE scroll container between sticky element and viewport
- **Avoid stacking context traps:** Don't apply `overflow-clip`, `overflow-hidden`, or `isolate` to containers with sticky children
- **ScrollArea `scrollbars` prop:** Use `scrollbars="vertical"` when horizontal scrolling is handled by child components

---

## Z-Index Hierarchy

```
z-30: Window chrome, toolbars
z-20: ScrollArea toolbars
z-10: Sticky section headers
z-auto: Normal content
```

---

## Tailwind Authoring Rules

Common mistakes the agent makes with utility classes. Catch these before they ship.

### Layout & Spacing

- Space flex/grid children with `gap-*` on the parent — not `mt-*`/`mb-*`/`mr-*`/`ml-*` on each child
- Flex items that contain truncated text or fluid content need `min-w-0` — without it they refuse to shrink past their intrinsic width
- Icons, avatars, and fixed-width elements inside flex containers need `shrink-0` so they don't compress
- When width and height are identical, write `size-{n}` instead of `h-{n} w-{n}`
- Use shorthand when both axes match — `p-4` not `px-4 py-4`

### Typography & Numbers

- Font-size and line-height classes (`text-*`, `leading-*`) belong on block elements (`<div>`, `<p>`, `<h1>`–`<h6>`) — never on inline elements like `<span>` or `<a>`
- Numeric values that update at runtime (counters, timers, stats, prices) need `tabular-nums` to prevent width jitter during updates
- Always use macOS typography tokens (`text-body`, `text-callout`, `text-headline`, etc.) — never raw Tailwind sizes like `text-sm` or `text-base`

### Class Hygiene

- Don't add display classes that match the element's default — `block` on `<div>` is redundant, `flex` on `<div>` is not
- Don't apply two conflicting values for the same property without a breakpoint or state variant to disambiguate them
- Integers and quarter-step values can be bare — `z-50` not `z-[50]`, `opacity-75` not `opacity-[0.75]`

### Colors

- Icon colors use solid tokens (`text-gray-9`), not alpha tokens (`text-gray-a9`)
- Prefer alpha color tokens for borders and dividers (`border-gray-a3`, `divide-gray-a4`) — they adapt to light and dark themes without needing `dark:` overrides
- Avoid opaque border colors like `border-gray-6` — they look harsh and need separate dark-mode values

---

## Avoiding Web-Style Cards

A common agent mistake is wrapping every piece of content in a bordered/shadowed card. Native macOS apps almost never do this — open Finder, Mail, Notes, or System Settings and you'll see flat content separated by structure, not decoration.

Glaze already provides the components that handle separation the macOS way:

| Instead of cards for...       | Use this                                                                     |
| ----------------------------- | ---------------------------------------------------------------------------- |
| A list of items               | `SidebarList` / `List.Root` — built-in spacing, selection, keyboard nav      |
| Grouped settings or fields    | `SidebarListGroup` with `SidebarListGroupTitle`, or a heading + `Separator`  |
| Side-by-side content regions  | `PanelGroup` + `Panel` — resizable, with native drag handles                 |
| Sections within a scroll view | A heading (`text-headlineEmphasized`) + content, separated by vertical space |
| Tabbed content areas          | `TabsRoot` + `Tabs` + `TabsContent`                                          |

When none of those fit and you genuinely need a bounded container, use a subtle approach:

- A single `Separator` or `border-b border-gray-a3` between siblings
- A recessed well (`bg-gray-2 rounded-lg p-3`) for secondary/nested content
- A bordered group (`border border-gray-a4 rounded-lg`) only when the content is independently interactive (clickable to open, draggable, etc.)

If you find yourself putting `shadow-*` + `border` + `rounded-xl` + `p-6` on a `<div>`, step back and check whether a Glaze layout component already handles the separation.

---

## Quick Checklist

Before submitting code:

- [ ] Read component `.md` files
- [ ] **No raw HTML equivalents** when a shared component exists (see FORBIDDEN table above)
- [ ] All component imports come from `@glaze/core/components`
- [ ] All hook imports come from `@glaze/core/hooks`
- [ ] All utility imports come from `@glaze/core/utils`
- [ ] Customization uses component props (variant, size, etc.) before className overrides
- [ ] Every panel has a `Toolbar`
- [ ] Window can be dragged
- [ ] Sidebar uses `searchable`/`actions` convenience props (not manual `toolbar` composition, unless custom layout needed)
- [ ] SidebarListItem uses props API (`icon`, `title`, `subtitle`, `accessory`) — children mode only for structural overrides
- [ ] SidebarListGroup uses `title` prop for section headers (prefer over `SidebarListGroupTitle` child unless you need custom styling)
- [ ] SidebarList uses managed selection (`items`, `selectedItem`, `onSelectedItemChange`, `getItemKey`) for data-driven lists
- [ ] Content panels use `<ToolbarContent>` + `<ToolbarActions>`
- [ ] `ToolbarTitle` is present only when it adds context; simple single-view apps omit it
- [ ] Content toolbar buttons use `variant="glass" size="large"` with `size-4.5` icons
- [ ] Using `SidebarList` and `List.Root`, not custom divs
- [ ] Keyboard navigation works (arrow keys)
- [ ] Flex/grid children use `gap-*` on parent, not margin between siblings
- [ ] Flex children that truncate have `min-w-0`; icons/fixed elements have `shrink-0`
- [ ] Changing numbers use `tabular-nums`
- [ ] Typography uses macOS tokens (`text-body`, `text-headline`, etc.), not raw `text-sm`/`text-base`
- [ ] One `variant="accent"` button per screen/dialog — all others use `filled` or `transparent`
- [ ] No web-style cards — used Glaze layout components (`List`, `SidebarList`, `PanelGroup`, `Separator`) for content separation

**When stuck:** Check the `.md` file for the component you're using.
