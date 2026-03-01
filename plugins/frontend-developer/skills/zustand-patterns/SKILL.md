---
name: zustand-patterns
description: Zustand store management with slices, middleware, selectors, and TypeScript patterns
---

# Zustand Patterns — Global State Management

## Overview

Zustand patterns for client state:
- Curried syntax with TypeScript
- Store slices organization
- Middleware (devtools, persist, immer)
- Granular selectors
- Feature-scoped vs global stores
- When to use Zustand vs TanStack Query vs Context

---

## Hard Rules

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- ALWAYS use curried syntax in TypeScript: `create<State>()((...) => ({...}))`
- NEVER destructure entire store — ALWAYS use granular selectors
- ALWAYS use `useShallow` when selecting multiple values
- ALWAYS define state + actions in one interface
- NEVER mutate state directly unless using immer middleware
- ALWAYS use `devtools` middleware in development
- ALWAYS use `partialize` with `persist` — NEVER persist entire store
- NEVER store server/API data in Zustand — use TanStack Query for server state
- ALWAYS reset stores between tests via `useStore.setState(useStore.getInitialState())`
- NEVER use Zustand for form state — use React Hook Form

</HARD-RULES>

---

## State Management Decision Matrix

| Concern | Tool | Why |
|---------|------|-----|
| Server/API data | TanStack Query | Caching, deduplication, background refresh |
| Global client state | Zustand | Lightweight, no boilerplate, fast |
| Local component state | `useState` / `useReducer` | Simplest option, no external deps |
| Rarely-changing tree-wide values | React Context | Theme, locale, auth user |
| Form state | React Hook Form | Validation, field management, performance |
| URL-driven state | Router search params | Shareable, bookmarkable, SSR-friendly |

**Rule:** If the data comes from an API, it goes in TanStack Query. If it's client-only UI state, use Zustand. If it's scoped to one component, use `useState`.

---

## Store Setup — Curried Syntax

### Why Curried Syntax?

TypeScript cannot infer generics on `create<State>()` without currying. The extra `()` enables full type inference.

```typescript
// ❌ BAD: Without currying — types not inferred correctly
const useStore = create<State>((set) => ({...}));

// ✅ GOOD: Curried syntax — full type inference
const useStore = create<State>()((...) => ({...}));
```

### Basic Store

```typescript
// src/stores/ui-store.ts
import { create } from 'zustand';

interface UIState {
  // State
  sidebarOpen: boolean;
  theme: 'light' | 'dark' | 'system';

  // Actions
  toggleSidebar: () => void;
  setSidebarOpen: (open: boolean) => void;
  setTheme: (theme: UIState['theme']) => void;
}

export const useUIStore = create<UIState>()((set) => ({
  // Initial state
  sidebarOpen: true,
  theme: 'system',

  // Actions
  toggleSidebar: () => set((state) => ({ sidebarOpen: !state.sidebarOpen })),
  setSidebarOpen: (open) => set({ sidebarOpen: open }),
  setTheme: (theme) => set({ theme }),
}));
```

---

## Granular Selectors

### Single Value Selector

```typescript
// ✅ GOOD: Select only what you need — component re-renders only when sidebarOpen changes
function Sidebar(): React.ReactElement {
  const sidebarOpen = useUIStore((state) => state.sidebarOpen);
  return sidebarOpen ? <nav>Sidebar content</nav> : null;
}
```

### Multiple Values with `useShallow`

```typescript
import { useShallow } from 'zustand/react/shallow';

// ✅ GOOD: useShallow prevents re-renders when unrelated state changes
function Header(): React.ReactElement {
  const { sidebarOpen, theme, toggleSidebar } = useUIStore(
    useShallow((state) => ({
      sidebarOpen: state.sidebarOpen,
      theme: state.theme,
      toggleSidebar: state.toggleSidebar,
    }))
  );

  return (
    <header>
      <button onClick={toggleSidebar}>
        {sidebarOpen ? 'Close' : 'Open'}
      </button>
      <span>Theme: {theme}</span>
    </header>
  );
}

// ❌ BAD: Destructuring entire store — re-renders on ANY state change
function Header(): React.ReactElement {
  const { sidebarOpen, theme, toggleSidebar } = useUIStore();
  // This re-renders when ANY store value changes, not just these three
}
```

### Reusable Selector Hooks

```typescript
// src/stores/selectors.ts
import { useUIStore } from './ui-store';

export function useSidebarOpen(): boolean {
  return useUIStore((state) => state.sidebarOpen);
}

export function useTheme(): UIState['theme'] {
  return useUIStore((state) => state.theme);
}

// Usage in components:
function Sidebar(): React.ReactElement {
  const sidebarOpen = useSidebarOpen();
  // ...
}
```

---

## Slices Pattern

For stores with multiple domains, split into slices that combine into one store.

### Auth Slice

```typescript
// src/stores/slices/auth-slice.ts
import type { StateCreator } from 'zustand';

interface User {
  id: string;
  email: string;
  name: string;
}

export interface AuthSlice {
  // State
  user: User | null;
  isAuthenticated: boolean;

  // Actions
  setUser: (user: User) => void;
  logout: () => void;
}

export const createAuthSlice: StateCreator<
  AuthSlice & UISlice, // Full store type for cross-slice access
  [],
  [],
  AuthSlice
> = (set) => ({
  user: null,
  isAuthenticated: false,

  setUser: (user) => set({ user, isAuthenticated: true }),
  logout: () => set({ user: null, isAuthenticated: false }),
});
```

### UI Slice

```typescript
// src/stores/slices/ui-slice.ts
import type { StateCreator } from 'zustand';

export interface UISlice {
  sidebarOpen: boolean;
  theme: 'light' | 'dark' | 'system';
  toggleSidebar: () => void;
  setTheme: (theme: UISlice['theme']) => void;
}

export const createUISlice: StateCreator<
  AuthSlice & UISlice,
  [],
  [],
  UISlice
> = (set) => ({
  sidebarOpen: true,
  theme: 'system',
  toggleSidebar: () => set((state) => ({ sidebarOpen: !state.sidebarOpen })),
  setTheme: (theme) => set({ theme }),
});
```

### Combining Slices

```typescript
// src/stores/app-store.ts
import { create } from 'zustand';
import { devtools, persist } from 'zustand/middleware';
import { immer } from 'zustand/middleware/immer';

import type { AuthSlice } from './slices/auth-slice';
import { createAuthSlice } from './slices/auth-slice';
import type { UISlice } from './slices/ui-slice';
import { createUISlice } from './slices/ui-slice';

type AppStore = AuthSlice & UISlice;

export const useAppStore = create<AppStore>()(
  devtools(
    persist(
      immer((...args) => ({
        ...createAuthSlice(...args),
        ...createUISlice(...args),
      })),
      {
        name: 'app-store',
        partialize: (state) => ({
          // Only persist these values — never entire store
          theme: state.theme,
          sidebarOpen: state.sidebarOpen,
        }),
      }
    ),
    { name: 'AppStore' }
  )
);
```

---

## Middleware

### Middleware Ordering

The correct nesting order (outermost to innermost):

```
devtools( persist( immer( storeCreator ) ) )
```

**Why this order:**
1. `devtools` wraps everything — sees final state changes
2. `persist` persists after immer processes
3. `immer` enables direct mutations in the innermost layer

### devtools — Development Debugging

```typescript
import { devtools } from 'zustand/middleware';

const useStore = create<State>()(
  devtools(
    (set) => ({
      count: 0,
      increment: () => set(
        (state) => ({ count: state.count + 1 }),
        undefined,
        'increment' // Action name in Redux DevTools
      ),
    }),
    { name: 'CounterStore' }
  )
);
```

### persist — LocalStorage

```typescript
import { persist } from 'zustand/middleware';

const useStore = create<State>()(
  persist(
    (set) => ({
      theme: 'system',
      sidebarOpen: true,
      user: null,         // Should NOT be persisted
      setTheme: (theme) => set({ theme }),
    }),
    {
      name: 'ui-preferences',
      // ✅ GOOD: Only persist what's needed
      partialize: (state) => ({
        theme: state.theme,
        sidebarOpen: state.sidebarOpen,
      }),
      // Optional: custom storage
      // storage: createJSONStorage(() => sessionStorage),
    }
  )
);
```

### immer — Direct Mutations

```typescript
import { immer } from 'zustand/middleware/immer';

interface TodoState {
  todos: Array<{ id: string; text: string; done: boolean }>;
  addTodo: (text: string) => void;
  toggleTodo: (id: string) => void;
  removeTodo: (id: string) => void;
}

const useTodoStore = create<TodoState>()(
  immer((set) => ({
    todos: [],
    addTodo: (text) =>
      set((state) => {
        // Direct mutation — immer handles immutability
        state.todos.push({ id: crypto.randomUUID(), text, done: false });
      }),
    toggleTodo: (id) =>
      set((state) => {
        const todo = state.todos.find((t) => t.id === id);
        if (todo) {
          todo.done = !todo.done;
        }
      }),
    removeTodo: (id) =>
      set((state) => {
        const index = state.todos.findIndex((t) => t.id === id);
        if (index !== -1) {
          state.todos.splice(index, 1);
        }
      }),
  }))
);
```

---

## Feature-Scoped Stores

For non-global state that belongs to a specific feature:

```typescript
// src/features/kanban/stores/kanban-store.ts
import { create } from 'zustand';

interface KanbanState {
  draggedCardId: string | null;
  activeColumn: string | null;
  setDraggedCard: (id: string | null) => void;
  setActiveColumn: (column: string | null) => void;
}

export const useKanbanStore = create<KanbanState>()((set) => ({
  draggedCardId: null,
  activeColumn: null,
  setDraggedCard: (id) => set({ draggedCardId: id }),
  setActiveColumn: (column) => set({ activeColumn: column }),
}));
```

**Rule:** Feature-scoped stores live in `src/features/<name>/stores/`. They are NOT imported by other features — only by the feature's own components and hooks.

---

## Testing Stores

### Reset Between Tests

```typescript
// test/setup.ts or in each test file
import { beforeEach } from 'vitest';
import { useAppStore } from '@/stores/app-store';

beforeEach(() => {
  // Reset to initial state between tests
  useAppStore.setState(useAppStore.getInitialState());
});
```

### Testing Store Logic (Without Rendering)

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { useAppStore } from '@/stores/app-store';

describe('AppStore - Auth Slice', () => {
  beforeEach(() => {
    useAppStore.setState(useAppStore.getInitialState());
  });

  it('sets user on login', () => {
    const user = { id: '1', email: 'test@example.com', name: 'Test' };
    useAppStore.getState().setUser(user);

    expect(useAppStore.getState().user).toEqual(user);
    expect(useAppStore.getState().isAuthenticated).toBe(true);
  });

  it('clears user on logout', () => {
    // Setup: log in first
    useAppStore.getState().setUser({ id: '1', email: 'test@example.com', name: 'Test' });

    // Act
    useAppStore.getState().logout();

    // Assert
    expect(useAppStore.getState().user).toBeNull();
    expect(useAppStore.getState().isAuthenticated).toBe(false);
  });
});
```

### Testing Components That Use Stores

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen } from '@/test/test-utils';
import userEvent from '@testing-library/user-event';
import { useUIStore } from '@/stores/ui-store';
import { Sidebar } from './Sidebar';

describe('Sidebar', () => {
  beforeEach(() => {
    useUIStore.setState(useUIStore.getInitialState());
  });

  it('shows sidebar when open', () => {
    useUIStore.setState({ sidebarOpen: true });
    render(<Sidebar />);
    expect(screen.getByRole('navigation')).toBeInTheDocument();
  });

  it('hides sidebar when closed', () => {
    useUIStore.setState({ sidebarOpen: false });
    render(<Sidebar />);
    expect(screen.queryByRole('navigation')).not.toBeInTheDocument();
  });

  it('toggles sidebar on button click', async () => {
    const user = userEvent.setup();
    render(<Sidebar />);

    await user.click(screen.getByRole('button', { name: /toggle/i }));
    expect(useUIStore.getState().sidebarOpen).toBe(false);
  });
});
```

---

## Common Mistakes

### ❌ Server State in Zustand

```typescript
// WRONG: API data in Zustand
const useStore = create<State>()((set) => ({
  users: [],
  fetchUsers: async () => {
    const users = await api.getUsers();
    set({ users }); // Stale immediately, no cache, no dedup
  },
}));

// CORRECT: Use TanStack Query for server state
const usersQuery = queryOptions({
  queryKey: ['users'],
  queryFn: fetchUsers,
});
```

### ❌ Destructuring Entire Store

```typescript
// WRONG: Re-renders on any state change
const { theme } = useStore();

// CORRECT: Re-renders only when theme changes
const theme = useStore((state) => state.theme);
```

### ❌ Persisting Sensitive Data

```typescript
// WRONG: Persisting auth tokens in localStorage
persist(store, {
  name: 'app',
  // No partialize = everything persisted, including tokens
});

// CORRECT: Only persist safe UI preferences
persist(store, {
  name: 'app',
  partialize: (state) => ({
    theme: state.theme,
    sidebarOpen: state.sidebarOpen,
    // Never persist: user, tokens, session data
  }),
});
```

---

## Summary

1. ✅ Curried syntax for TypeScript inference
2. ✅ Granular selectors, `useShallow` for multiple values
3. ✅ Slices pattern for organized domain logic
4. ✅ Middleware ordering: `devtools(persist(immer(...)))`
5. ✅ `partialize` on persist — never persist entire store
6. ✅ Server state in TanStack Query, client state in Zustand
7. ✅ Reset stores in tests via `getInitialState()`
