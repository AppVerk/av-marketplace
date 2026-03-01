---
name: coding-standards
description: TypeScript + React coding standards, architecture patterns, naming conventions, ESLint configuration
---

# Coding Standards — TypeScript + React

## Overview

Foundational rules for TypeScript + React development. Enforced in all code:
- Strict TypeScript configuration
- React best practices
- Feature-based architecture (Bulletproof React)
- Three-layer separation of concerns
- Naming conventions
- ESLint rules

---

## TypeScript Hard Rules

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- NEVER use `any` — use `unknown` + type guards instead
- NEVER use `as` type assertions except `as const`
- NEVER use `!` non-null assertion — use optional chaining `?.` and nullish coalescing `??`
- NEVER use `enum` — use `as const` objects + derived union types
- NEVER use `@ts-ignore` — use `@ts-expect-error` with comment if absolutely unavoidable
- ALWAYS use `interface` for object shapes, `type` for unions/intersections
- NEVER use `I` prefix on interfaces (`User`, not `IUser`)
- ALWAYS use `import type { }` for type-only imports
- ALWAYS annotate all function parameters and return types explicitly
- NEVER use `export *` or barrel exports >5 re-exports
- NEVER leave unused imports or variables

</HARD-RULES>

### Configuration Requirements

**tsconfig.json MUST include:**

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "isolatedModules": true,
    "noImplicitAny": true,
    "noImplicitThis": true,
    "strictNullChecks": true,
    "strictFunctionTypes": true,
    "strictBindCallApply": true,
    "strictPropertyInitialization": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "paths": {
      "@/*": ["./src/*"]
    }
  }
}
```

### Type Annotations

- Explicitly annotate ALL function parameters and return types, even when TypeScript could infer them
- Use modern union syntax: `T | null` instead of `T | undefined` unless specifically undefined
- For optional properties: `prop?: T` (equivalent to `prop: T | undefined`)
- For potentially null values: use `T | null`
- Never rely on implicit type inference for public APIs

**Example:**

```typescript
// ❌ BAD: Missing parameter and return types
function processUser(user) {
  return user.name.toUpperCase();
}

// ✅ GOOD: All types explicit
function processUser(user: User): string {
  return user.name.toUpperCase();
}

// ❌ BAD: Using type assertion
const id = userId as number;

// ✅ GOOD: Type guard or explicit context
function handleUser(userId: string | number): void {
  if (typeof userId === 'number') {
    // userId is number here
  }
}
```

### Interfaces vs Types

- Use `interface` for object shapes (especially component props)
- Use `type` for unions, intersections, tuples, primitives
- Don't extend unions or use union on interfaces

**Example:**

```typescript
// ✅ GOOD: Interface for props
interface ButtonProps {
  variant: 'primary' | 'secondary';
  disabled?: boolean;
  children: React.ReactNode;
}

// ✅ GOOD: Type for union
type Status = 'idle' | 'loading' | 'success' | 'error';

// ✅ GOOD: Type for intersection
type WithTimestamp = { createdAt: Date };
type User = { id: string; name: string } & WithTimestamp;
```

### Import Organization

- Group imports: standard library, third-party, then local
- One import per line; never use wildcards (`import *`)
- Separate type imports: `import type { SomeType } from '...'`
- No imports inside functions — all at the top of file

**Example:**

```typescript
// ✅ GOOD: Organized imports
import { useState } from 'react';
import type { ReactNode } from 'react';

import { QueryClient } from '@tanstack/react-query';

import type { User } from '@/types/user';
import { useAuth } from '@/features/auth';
```

---

## React Hard Rules

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- NEVER use `React.FC` — use named function with direct props annotation
- NEVER use `children` implicitly — ALWAYS explicitly annotate `children: ReactNode` in props
- NEVER use `fireEvent` in tests — ALWAYS use `userEvent`
- NEVER use `getByText` as first choice — prefer `screen.getByRole`
- NEVER use `getByTestId` without strong justification
- NEVER use bare `onClick` handlers without specific types
- NEVER use `any` for event handlers — use React-specific types
- NEVER use `ref.current!` — use optional chaining or proper type narrowing
- NEVER create Context without a custom hook to access it
- NEVER use global Context default of `undefined` — throw in the hook instead

</HARD-RULES>

### Component Props

- Use direct props annotation, never `React.FC<Props>`
- Explicitly include `children: React.ReactNode` if component accepts children
- Use `Props` suffix for interfaces (`ButtonProps`, `CardProps`)

**Example:**

```typescript
// ❌ BAD: Using React.FC
const Button: React.FC<{ label: string; onClick: () => void }> = ({ label, onClick }) => (
  <button onClick={onClick}>{label}</button>
);

// ✅ GOOD: Direct props annotation with children
interface ButtonProps {
  label: string;
  onClick: () => void;
  children?: React.ReactNode;
  disabled?: boolean;
}

function Button({ label, onClick, children, disabled }: ButtonProps): React.ReactElement {
  return (
    <button onClick={onClick} disabled={disabled}>
      {label} {children}
    </button>
  );
}
```

### Event Handler Types

- Use specific React event types: `React.MouseEvent<HTMLButtonElement>`, `React.ChangeEvent<HTMLInputElement>`
- Never use `any` for event parameters
- Type handlers in props with specific event types

**Example:**

```typescript
interface FormProps {
  onSubmit: (event: React.FormEvent<HTMLFormElement>) => void;
  onChange: (event: React.ChangeEvent<HTMLInputElement>) => void;
}

function Form({ onSubmit, onChange }: FormProps): React.ReactElement {
  return (
    <form onSubmit={onSubmit}>
      <input onChange={onChange} />
    </form>
  );
}
```

### Hooks Rules

- Never call hooks inside conditions, loops, or nested functions
- Always use hooks at the top level of a function component
- Custom hooks must start with `use` prefix
- List all dependencies in dependency arrays — never omit or use empty array to suppress warnings

**Example:**

```typescript
// ❌ BAD: Hook inside condition
function Component({ shouldFetch }: { shouldFetch: boolean }): React.ReactElement {
  if (shouldFetch) {
    const data = useFetch(); // WRONG!
  }
  return <div />;
}

// ✅ GOOD: Hook at top level
function Component({ shouldFetch }: { shouldFetch: boolean }): React.ReactElement {
  const data = useFetch();
  if (!shouldFetch) return <div />;
  return <div>{data}</div>;
}
```

### Context Patterns

- Default value in `createContext` should be `null` or `undefined`
- Create a custom hook to access context — this hook should throw if context is not available
- Never use context as a component wrapper without explicit exports

**Example:**

```typescript
// ❌ BAD: Context without typed hook
const ThemeContext = React.createContext<Theme | undefined>(undefined);

// ✅ GOOD: Context with typed hook
const ThemeContext = React.createContext<Theme | null>(null);

function useTheme(): Theme {
  const theme = React.useContext(ThemeContext);
  if (theme === null) {
    throw new Error('useTheme must be used within ThemeProvider');
  }
  return theme;
}

interface ThemeProviderProps {
  children: React.ReactNode;
}

function ThemeProvider({ children }: ThemeProviderProps): React.ReactElement {
  const [theme, setTheme] = React.useState<Theme>(defaultTheme);
  return (
    <ThemeContext.Provider value={theme}>
      {children}
    </ThemeContext.Provider>
  );
}
```

---

## Feature-Based Architecture

### Directory Structure

```
src/
├── app/                    # Shell: routes, providers, entry point
│   ├── App.tsx            # Main route component
│   └── Root.tsx           # Root with providers
├── features/              # Self-contained feature modules
│   ├── auth/
│   │   ├── api/           # API calls + TanStack Query hooks
│   │   ├── components/    # Feature-scoped UI
│   │   ├── hooks/         # Feature-scoped logic hooks
│   │   ├── stores/        # Feature-scoped Zustand stores
│   │   ├── types/         # Feature-scoped types
│   │   └── index.ts       # Public API (max 5 exports)
│   ├── dashboard/
│   │   ├── api/
│   │   ├── components/
│   │   └── ...
│   └── users/
│       └── ...
├── components/            # Shared UI (Button, Modal, Card)
│   └── ui/               # Primitives (shadcn/ui style)
├── hooks/                # Shared hooks (useDebounce, useMediaQuery)
├── lib/                  # Preconfigured libs (axios instance, cn utility)
├── stores/               # Global state stores
├── types/                # Shared TypeScript types
├── utils/                # Pure utility functions
└── test/                 # Test setup, custom render, MSW handlers
```

### Dependency Rules (NON-NEGOTIABLE)

**Direction:** `shared -> features -> app`

- ✅ Features can import from `shared/` (hooks, utils, components, types, lib, stores)
- ✅ App can import from `features/` and `shared/`
- ❌ Features NEVER import from other features
- ❌ Shared code NEVER imports from features or app

Cross-feature composition happens ONLY in `app/` (root routes/pages).

**Example:**

```typescript
// ✅ GOOD: Auth feature imports shared utilities
import { formatDate } from '@/utils/format'; // from shared utils
import { Button } from '@/components/ui/button'; // from shared components
import type { User } from '@/types/user'; // from shared types

// ❌ BAD: Auth feature imports from orders feature
import { useOrders } from '@/features/orders/hooks'; // WRONG!

// ✅ GOOD: App composes features together
import { AuthPage } from '@/features/auth';
import { DashboardPage } from '@/features/dashboard';
```

### Three-Layer Separation of Concerns

**Layer 1: API/Service Layer**
- Pure functions, no React imports
- Fully testable without rendering
- Located in `features/<name>/api/<name>Api.ts`
- Exported in `features/<name>/api/queries.ts` for TanStack Query

**Layer 2: Logic/Hook Layer**
- Custom hooks bridging React state and services
- Located in `features/<name>/hooks/`
- Handles API calls, state management, side effects

**Layer 3: UI/Component Layer**
- Rendering only, minimal logic
- Located in `features/<name>/components/`
- Receives data from hooks, calls handlers

**Example:**

```typescript
// Layer 1: API service (pure function)
// features/users/api/usersApi.ts
export async function fetchUser(id: string): Promise<User> {
  const response = await apiClient.get(`/users/${id}`);
  return response.data;
}

// Layer 2: Hook (TanStack Query + Zustand)
// features/users/hooks/useUser.ts
export function useUser(id: string): {
  user: User | undefined;
  isLoading: boolean;
  error: Error | null;
} {
  const { data: user, isLoading, error } = useQuery({
    queryKey: ['users', id],
    queryFn: () => fetchUser(id),
  });
  return { user, isLoading, error };
}

// Layer 3: Component (UI only)
// features/users/components/UserCard.tsx
interface UserCardProps {
  userId: string;
}

function UserCard({ userId }: UserCardProps): React.ReactElement {
  const { user, isLoading } = useUser(userId);

  if (isLoading) return <div>Loading...</div>;
  if (!user) return <div>User not found</div>;

  return <div>{user.name}</div>;
}
```

---

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Directories | `kebab-case` | `user-profile/`, `auth-modal/` |
| Component files | `PascalCase.tsx` | `UserProfile.tsx`, `LoginForm.tsx` |
| Component exports | `PascalCase` function | `export function UserProfile() {}` |
| Hook files | `camelCase` with `use` prefix | `useAuth.ts`, `useFormData.ts` |
| Hook exports | `camelCase` with `use` prefix | `export function useAuth()` |
| Utility functions | `camelCase` | `formatDate.ts`, `calculateTotal.ts` |
| Types/Interfaces | `PascalCase` | `User`, `ButtonProps`, `FormData` |
| Constants | `UPPER_SNAKE_CASE` | `API_BASE_URL`, `MAX_RETRIES` |
| Const objects | `PascalCase` + `as const` | `const OrderStatus = {...} as const` |
| Test files | `.test.tsx` for components, `.spec.ts` for e2e | `Button.test.tsx`, `auth.spec.ts` |

### Props Naming

- Always use `Props` suffix: `ButtonProps`, `CardProps`, `ModalProps`
- Optional props use `?`: `disabled?: boolean`
- Event handlers start with `on`: `onClick`, `onChange`, `onSubmit`

**Example:**

```typescript
interface UserProfileProps {
  userId: string;
  onLogout?: () => void;
  disabled?: boolean;
}

function UserProfile({ userId, onLogout, disabled }: UserProfileProps): React.ReactElement {
  // ...
}
```

---

## ESLint Configuration

### Required Rules

```javascript
// eslint.config.js
export default [
  {
    files: ['**/*.{ts,tsx}'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-non-null-assertion': 'error',
      '@typescript-eslint/consistent-type-imports': [
        'error',
        { prefer: 'type-imports', fixStyle: 'inline-type-imports' }
      ],
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
      '@typescript-eslint/explicit-function-return-types': 'error',
      '@typescript-eslint/explicit-module-boundary-types': 'error',
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      'no-var': 'error',
      'prefer-const': 'error',
    },
  },
];
```

### Recommended Plugins

- `@typescript-eslint/eslint-plugin` with `strict-type-checked` + `stylistic-type-checked`
- `eslint-plugin-react-hooks`
- `eslint-plugin-import` for import ordering
- Biome as alternative if detected in project

---

## Path Aliases

All imports from `src/` use `@/` instead of relative paths.

**tsconfig.json:**

```json
{
  "compilerOptions": {
    "paths": {
      "@/*": ["./src/*"]
    }
  }
}
```

**vite.config.ts:**

```typescript
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
});
```

**Always use path aliases:**

```typescript
// ❌ BAD: Relative imports
import { Button } from '../../../../components/ui/button';

// ✅ GOOD: Path aliases
import { Button } from '@/components/ui/button';
```

---

## Code Organization

### File Ordering in Components

1. Imports (standard library, third-party, local)
2. Types/Interfaces
3. Component function
4. Exports

**Example:**

```typescript
import { useState } from 'react';
import type { ReactNode } from 'react';

import clsx from 'clsx';

import type { User } from '@/types/user';
import { Button } from '@/components/ui/button';

interface UserCardProps {
  user: User;
  onSelect: (id: string) => void;
}

export function UserCard({ user, onSelect }: UserCardProps): ReactNode {
  const [isHovered, setIsHovered] = useState(false);

  return (
    <div
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      className={clsx('p-4', isHovered && 'bg-gray-100')}
    >
      <h3>{user.name}</h3>
      <Button onClick={() => onSelect(user.id)}>Select</Button>
    </div>
  );
}
```

### Documentation

- Keep comments minimal and explanatory (WHY, not WHAT)
- Write concise docstrings for public APIs
- Document component props in interface definition
- Never change existing comments unless fixing the issue they describe

**Example:**

```typescript
/**
 * Formats a user's display name, handling cases where
 * firstName or lastName might be missing.
 */
export function formatUserName(
  firstName: string | null,
  lastName: string | null,
): string {
  // Prefer full name, fall back to firstName, then lastName
  if (firstName && lastName) return `${firstName} ${lastName}`;
  return firstName ?? lastName ?? 'Unknown User';
}
```

---

## Summary

All code must follow these standards:
1. ✅ Strict TypeScript with no `any`, `as`, `!`
2. ✅ React components with explicit props, no `React.FC`
3. ✅ Feature-based architecture with dependency rules
4. ✅ Path aliases for all imports
5. ✅ Clear naming conventions
6. ✅ ESLint configured and enforced
7. ✅ Three-layer separation (API, Hook, UI)
