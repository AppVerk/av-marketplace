---
name: tailwind-patterns
description: Tailwind CSS v4, CVA component variants, shadcn/ui patterns, semantic tokens, responsive design
---

# Tailwind CSS Patterns — v4 + Component System

## Overview

Modern Tailwind v4 setup and component patterns:
- CSS-first configuration (no tailwind.config.js)
- `cn()` utility for conditional classes
- CVA (Class Variance Authority) for variants
- shadcn/ui architecture
- Semantic tokens with dark mode
- Accessibility patterns

---

## Hard Rules

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- NEVER use `@apply` for CSS abstractions — extract React components instead
- NEVER dynamically construct class names (`bg-${color}-500`) — use const maps
- NEVER use magic values or overuse arbitrary values (`w-[347px]`) — define tokens in `@theme`
- ALWAYS use semantic tokens (`bg-primary`) instead of raw palette colors (`bg-blue-500`)
- NEVER remove focus outline without replacement — ALWAYS pair `focus:outline-none` with `focus-visible:ring-2`
- ALWAYS use `focus-visible:` instead of `focus:` for ring/outline styles
- ALWAYS design mobile-first — unprefixed classes = all screen sizes
- ALWAYS use container queries (`@container`) for components, viewport queries (`md:`) for page layout only
- ALWAYS use `cn()` for conditional class concatenation — never string interpolation
- NEVER install `tailwind.config.js` in v4 projects — use CSS-first `@theme` configuration

</HARD-RULES>

---

## Vite + Tailwind v4 Setup

### Installation

```bash
pnpm add -D tailwindcss @tailwindcss/vite
```

### Vite Configuration

```typescript
// vite.config.ts
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
  ],
});
```

**No PostCSS config needed. No `tailwind.config.js`. Tailwind v4 uses CSS-first configuration.**

### CSS Entry Point

```css
/* src/index.css */
@import "tailwindcss";

/* ---- Design Tokens ---- */
@theme {
  /* Colors - Semantic */
  --color-primary: oklch(0.55 0.22 265);
  --color-primary-foreground: oklch(0.98 0.01 265);
  --color-secondary: oklch(0.75 0.05 265);
  --color-secondary-foreground: oklch(0.15 0.02 265);
  --color-destructive: oklch(0.55 0.22 25);
  --color-destructive-foreground: oklch(0.98 0.01 25);
  --color-muted: oklch(0.92 0.01 265);
  --color-muted-foreground: oklch(0.55 0.02 265);
  --color-accent: oklch(0.92 0.04 265);
  --color-accent-foreground: oklch(0.15 0.02 265);

  /* Colors - Surface */
  --color-background: oklch(0.99 0.005 265);
  --color-foreground: oklch(0.12 0.02 265);
  --color-card: oklch(0.99 0.005 265);
  --color-card-foreground: oklch(0.12 0.02 265);
  --color-border: oklch(0.88 0.01 265);
  --color-input: oklch(0.88 0.01 265);
  --color-ring: oklch(0.55 0.22 265);

  /* Typography */
  --font-sans: 'Inter Variable', 'Inter', ui-sans-serif, system-ui, sans-serif;
  --font-mono: 'JetBrains Mono Variable', ui-monospace, monospace;

  /* Border Radius */
  --radius-sm: 0.25rem;
  --radius-md: 0.375rem;
  --radius-lg: 0.5rem;
  --radius-xl: 0.75rem;

  /* Spacing Scale (extend defaults) */
  --spacing-18: 4.5rem;
  --spacing-88: 22rem;
  --spacing-128: 32rem;

  /* Shadows */
  --shadow-soft: 0 1px 3px oklch(0 0 0 / 0.08), 0 1px 2px oklch(0 0 0 / 0.04);
}

/* ---- Dark Mode ---- */
@custom-variant dark (&:is(.dark *));

@layer base {
  .dark {
    --color-primary: oklch(0.75 0.18 265);
    --color-primary-foreground: oklch(0.12 0.02 265);
    --color-background: oklch(0.15 0.01 265);
    --color-foreground: oklch(0.92 0.01 265);
    --color-card: oklch(0.18 0.01 265);
    --color-card-foreground: oklch(0.92 0.01 265);
    --color-border: oklch(0.3 0.01 265);
    --color-input: oklch(0.3 0.01 265);
    --color-muted: oklch(0.22 0.01 265);
    --color-muted-foreground: oklch(0.6 0.01 265);
    --color-accent: oklch(0.25 0.03 265);
    --color-accent-foreground: oklch(0.92 0.01 265);
    --color-ring: oklch(0.75 0.18 265);
  }
}
```

---

## `cn()` Utility (MANDATORY)

Every component with conditional classes MUST use `cn()`.

### Setup

```bash
pnpm add clsx tailwind-merge
```

```typescript
// src/lib/utils.ts
import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}
```

### Usage

```typescript
import { cn } from '@/lib/utils';

interface CardProps {
  className?: string;
  isActive?: boolean;
  children: React.ReactNode;
}

function Card({ className, isActive, children }: CardProps): React.ReactElement {
  return (
    <div
      className={cn(
        'rounded-lg border bg-card p-6 shadow-soft',
        isActive && 'border-primary ring-2 ring-primary/20',
        className
      )}
    >
      {children}
    </div>
  );
}
```

**Why `cn()` over plain template literals:**

```typescript
// ❌ BAD: Template literal — conflicts not resolved
<div className={`p-4 ${isLarge ? 'p-8' : ''}`} />
// Result: "p-4 p-8" — both applied, unpredictable winner

// ✅ GOOD: cn() — tailwind-merge resolves conflicts
<div className={cn('p-4', isLarge && 'p-8')} />
// Result: "p-8" — last conflicting class wins
```

---

## CVA (Class Variance Authority)

Every component with variants (Button, Badge, Alert, Input) MUST use CVA.

### Installation

```bash
pnpm add class-variance-authority
```

### Button Example (Full Pattern)

```typescript
// src/components/ui/button.tsx
import { type VariantProps, cva } from 'class-variance-authority';
import { forwardRef } from 'react';

import { cn } from '@/lib/utils';

const buttonVariants = cva(
  // Base styles (always applied)
  'inline-flex items-center justify-center gap-2 rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50',
  {
    variants: {
      variant: {
        default: 'bg-primary text-primary-foreground hover:bg-primary/90',
        destructive: 'bg-destructive text-destructive-foreground hover:bg-destructive/90',
        outline: 'border border-input bg-background hover:bg-accent hover:text-accent-foreground',
        secondary: 'bg-secondary text-secondary-foreground hover:bg-secondary/80',
        ghost: 'hover:bg-accent hover:text-accent-foreground',
        link: 'text-primary underline-offset-4 hover:underline',
      },
      size: {
        sm: 'h-8 rounded-md px-3 text-xs',
        md: 'h-10 px-4 py-2',
        lg: 'h-12 rounded-lg px-6 text-base',
        icon: 'size-10',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'md',
    },
  }
);

interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  children: React.ReactNode;
}

const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, children, ...props }, ref) => (
    <button
      className={cn(buttonVariants({ variant, size, className }))}
      ref={ref}
      {...props}
    >
      {children}
    </button>
  )
);
Button.displayName = 'Button';

export { Button, buttonVariants };
export type { ButtonProps };
```

### Usage

```typescript
<Button>Default</Button>
<Button variant="destructive" size="lg">Delete</Button>
<Button variant="outline" className="w-full">Full Width</Button>
```

### Badge Example

```typescript
// src/components/ui/badge.tsx
import { type VariantProps, cva } from 'class-variance-authority';

import { cn } from '@/lib/utils';

const badgeVariants = cva(
  'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold transition-colors',
  {
    variants: {
      variant: {
        default: 'bg-primary text-primary-foreground',
        secondary: 'bg-secondary text-secondary-foreground',
        destructive: 'bg-destructive text-destructive-foreground',
        outline: 'border text-foreground',
        success: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-100',
        warning: 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-100',
      },
    },
    defaultVariants: {
      variant: 'default',
    },
  }
);

interface BadgeProps
  extends React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {}

function Badge({ className, variant, ...props }: BadgeProps): React.ReactElement {
  return <span className={cn(badgeVariants({ variant, className }))} {...props} />;
}

export { Badge, badgeVariants };
export type { BadgeProps };
```

---

## Component Architecture — shadcn/ui Pattern

### Two-Layer Architecture

1. **Behavior layer** — Radix UI primitives (keyboard navigation, ARIA, focus management)
2. **Styling layer** — Tailwind + CVA (visual presentation)

Components live in `src/components/ui/` — they are owned code, not npm-installed.

### Example: Dialog Component

```typescript
// src/components/ui/dialog.tsx
import * as DialogPrimitive from '@radix-ui/react-dialog';
import { X } from 'lucide-react';
import { forwardRef } from 'react';

import { cn } from '@/lib/utils';

const Dialog = DialogPrimitive.Root;
const DialogTrigger = DialogPrimitive.Trigger;
const DialogPortal = DialogPrimitive.Portal;
const DialogClose = DialogPrimitive.Close;

const DialogOverlay = forwardRef<
  React.ElementRef<typeof DialogPrimitive.Overlay>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Overlay>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Overlay
    ref={ref}
    className={cn(
      'fixed inset-0 z-50 bg-black/80 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0',
      className
    )}
    {...props}
  />
));
DialogOverlay.displayName = DialogPrimitive.Overlay.displayName;

const DialogContent = forwardRef<
  React.ElementRef<typeof DialogPrimitive.Content>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Content>
>(({ className, children, ...props }, ref) => (
  <DialogPortal>
    <DialogOverlay />
    <DialogPrimitive.Content
      ref={ref}
      className={cn(
        'fixed left-1/2 top-1/2 z-50 grid w-full max-w-lg -translate-x-1/2 -translate-y-1/2 gap-4 border bg-background p-6 shadow-lg duration-200 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[state=closed]:slide-out-to-left-1/2 data-[state=closed]:slide-out-to-top-[48%] data-[state=open]:slide-in-from-left-1/2 data-[state=open]:slide-in-from-top-[48%] sm:rounded-lg',
        className
      )}
      {...props}
    >
      {children}
      <DialogPrimitive.Close className="absolute right-4 top-4 rounded-sm opacity-70 ring-offset-background transition-opacity hover:opacity-100 focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:pointer-events-none data-[state=open]:bg-accent data-[state=open]:text-muted-foreground">
        <X className="size-4" />
        <span className="sr-only">Close</span>
      </DialogPrimitive.Close>
    </DialogPrimitive.Content>
  </DialogPortal>
));
DialogContent.displayName = DialogPrimitive.Content.displayName;

export { Dialog, DialogTrigger, DialogContent, DialogClose };
```

### When to Extract Components vs Utility Classes

| Situation | Solution |
|-----------|----------|
| Reused visual pattern with behavior | Extract React component with CVA |
| Conditional class logic | Use `cn()` in the component |
| Consistent spacing/sizing tokens | Define in `@theme` |
| One-off layout adjustment | Inline Tailwind classes (no extraction) |
| Repeated long class strings (3+ places) | Extract React component (never `@apply`) |

---

## Dynamic Classes — The Safe Way

**Never dynamically construct class names:**

```typescript
// ❌ BAD: Dynamic class construction — Tailwind can't detect these
const color = 'blue';
<div className={`bg-${color}-500 text-${color}-100`} />;

// ✅ GOOD: Const map with full class names
const StatusColors = {
  success: 'bg-green-100 text-green-800',
  warning: 'bg-yellow-100 text-yellow-800',
  error: 'bg-red-100 text-red-800',
  info: 'bg-blue-100 text-blue-800',
} as const;

type Status = keyof typeof StatusColors;

interface StatusBadgeProps {
  status: Status;
  children: React.ReactNode;
}

function StatusBadge({ status, children }: StatusBadgeProps): React.ReactElement {
  return (
    <span className={cn('rounded-full px-2 py-1 text-sm font-medium', StatusColors[status])}>
      {children}
    </span>
  );
}
```

---

## Responsive Design

### Mobile-First (MANDATORY)

Unprefixed classes = base / all screens. Add prefixes for larger screens.

```typescript
// ✅ GOOD: Mobile-first
<div className="flex flex-col gap-4 md:flex-row md:gap-8 lg:gap-12">
  <aside className="w-full md:w-64 lg:w-80">Sidebar</aside>
  <main className="flex-1">Content</main>
</div>

// ❌ BAD: Desktop-first (hiding on mobile)
<div className="hidden md:flex">Desktop only</div>
```

### Container Queries vs Viewport Queries

| Query Type | Use For | Example |
|-----------|---------|---------|
| Viewport (`md:`, `lg:`) | Page-level layout, navigation, sidebars | `md:grid-cols-2 lg:grid-cols-3` |
| Container (`@container`) | Component-level responsiveness | `@md:flex-row @lg:gap-8` |

```typescript
// Container query setup
<div className="@container">
  <div className="flex flex-col @md:flex-row @md:items-center gap-4">
    <img className="size-16 @md:size-20 rounded-full" />
    <div className="flex-1">
      <h3 className="text-base @lg:text-lg font-semibold">Name</h3>
      <p className="text-sm text-muted-foreground">Description</p>
    </div>
  </div>
</div>
```

---

## Accessibility Patterns

### Screen Reader Content

```typescript
// sr-only for label content
<button>
  <X className="size-4" />
  <span className="sr-only">Close dialog</span>
</button>
```

### Focus Management

```typescript
// ✅ GOOD: focus-visible (only shows ring on keyboard navigation)
<button className="focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2">
  Click me
</button>

// ❌ BAD: focus (shows ring on mouse click too)
<button className="focus:ring-2 focus:ring-ring">
  Click me
</button>

// ❌ BAD: Removing focus without replacement
<button className="focus:outline-none">
  Click me
</button>
```

### Motion Reduction

```typescript
// Every animation must respect prefers-reduced-motion
<div className="animate-spin motion-reduce:animate-none" />

<div className="transition-transform duration-300 motion-reduce:duration-0 hover:scale-105 motion-reduce:hover:scale-100" />
```

### ARIA State Variants

```typescript
// Use ARIA state variants instead of manual class toggling
<button
  aria-expanded={isOpen}
  className="aria-expanded:rotate-180 transition-transform"
>
  <ChevronDown />
</button>

<li
  aria-selected={isSelected}
  className="aria-selected:bg-primary aria-selected:text-primary-foreground"
>
  {item.label}
</li>
```

### Semantic HTML

```typescript
// ✅ GOOD: Semantic HTML
<nav aria-label="Main navigation">{/* links */}</nav>
<main>{/* page content */}</main>
<button onClick={handleAction}>Do something</button>
<label htmlFor="email">Email</label>
<input id="email" type="email" />

// ❌ BAD: Non-semantic divs with click handlers
<div onClick={handleAction}>Do something</div>
<div className="nav">{/* links */}</div>
```

---

## Summary

1. ✅ Tailwind v4 with CSS-first `@theme` configuration
2. ✅ `cn()` for all conditional class logic
3. ✅ CVA for every component with variants
4. ✅ shadcn/ui two-layer pattern (behavior + styling)
5. ✅ Semantic tokens, never raw palette colors
6. ✅ Mobile-first responsive design
7. ✅ Container queries for component-level responsiveness
8. ✅ Accessibility: sr-only, focus-visible, motion-reduce, ARIA variants
