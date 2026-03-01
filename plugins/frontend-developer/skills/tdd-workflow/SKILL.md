---
name: tdd-workflow
description: Test-driven development workflow with Vitest, React Testing Library, MSW v2, and Playwright
---

# TDD Workflow — Testing Strategy

## Overview

Enforces red-green-refactor TDD cycle with comprehensive testing strategy:
- Vitest + jsdom for component/unit tests
- React Testing Library for user-centric testing
- MSW v2 for API mocking
- Playwright for E2E critical paths
- Testing Trophy approach (pyramid inverted)
- 80%+ coverage requirement

---

## Testing Trophy

```
         /\
        /E2E\           5-10% — Playwright critical paths
       /------\
      / Integr. \       Largest layer — RTL + MSW
     /  ation    \      "Write tests. Not too many. Mostly integration."
    /--------------\
   /  Unit tests    \   Hooks, utils, store logic, pure functions
  /------------------\
 / Static (TypeScript) \ Foundation — errors caught at compile time
/________________________\
```

### Layer Breakdown

**Static Analysis (Foundation)**
- TypeScript strict mode catches type errors at compile time
- ESLint/Biome catch code smells and incorrect patterns
- No runtime cost

**Unit Tests (10-15%)**
- Test pure functions: `formatDate()`, `calculateTotal()`, `parseQueryString()`
- Test hook logic: `useAuth()`, `useFormData()` without rendering
- Test store logic: Zustand selectors, state updates
- Run fast, isolated, deterministic

**Integration Tests (Largest Layer — 60-75%)**
- Test features end-to-end with user interactions
- Use React Testing Library to test behavior, not implementation
- Mock external APIs with MSW
- Test user workflows: login, create item, update, delete

**E2E Tests (5-10%)**
- Test critical user paths: signup → email verification → dashboard
- Test multi-step flows: checkout process, complex workflows
- Run in real browser with Playwright
- Slow and expensive — only critical paths

---

## Hard Rules

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- NEVER write implementation before tests — TDD: Red → Green → Refactor
- NEVER use `fireEvent` — ALWAYS use `userEvent`
- NEVER use `getByText` as first choice — prefer `screen.getByRole`
- NEVER use `getByTestId` without strong justification
- NEVER test implementation details (state, internal methods, class names)
- NEVER use manual `act()` wrapping around `render()` or `userEvent` — React Testing Library handles it
- NEVER share mutable state in `beforeEach` — inline setup in each test
- NEVER mock fetch/axios with `vi.mock()` — ALWAYS use MSW for API mocking
- NEVER skip tests or commit with `xit`, `skip`, `pending`
- ALWAYS aim for 80%+ coverage before completion
- ALWAYS keep tests co-located with code (`Button.tsx` + `Button.test.tsx`)
- ALWAYS run full suite (`pnpm test`) not just individual files during development

</HARD-RULES>

---

## File Organization

### Structure

```
src/
  features/auth/
    components/
      LoginForm.tsx
      LoginForm.test.tsx              # co-located
    hooks/
      useAuth.ts
      useAuth.test.ts                 # co-located
    api/
      authApi.ts
      authApi.test.ts                 # co-located
  mocks/
    handlers.ts                       # MSW handlers (centralized)
    server.ts                         # MSW server setup
  test/
    setup.ts                          # Vitest setup file
    test-utils.tsx                    # Custom render with providers
e2e/
  pages/
    LoginPage.ts                      # Page Object Model
    DashboardPage.ts
  tests/
    auth.spec.ts                      # E2E tests
    checkout.spec.ts
```

### File Naming Convention

| Test Type | Pattern | Location |
|-----------|---------|----------|
| Unit / Integration | `*.test.{ts,tsx}` | Co-located in `src/` |
| E2E | `*.spec.ts` | `e2e/tests/` |
| Page Objects | `*Page.ts` | `e2e/pages/` |

---

## Custom Render (REQUIRED)

Every project must have `src/test/test-utils.tsx` with custom render wrapping components in all required providers.

**Example:**

```typescript
// src/test/test-utils.tsx
import type { ReactElement } from 'react';
import { ReactQueryDevtools } from '@tanstack/react-query-devtools';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { RenderOptions, render } from '@testing-library/react';
import type { Router } from '@tanstack/react-router';
import { RouterProvider } from '@tanstack/react-router';

const createTestQueryClient = (): QueryClient =>
  new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
        gcTime: 0,
      },
      mutations: {
        retry: false,
      },
    },
  });

interface ExtendedRenderOptions extends Omit<RenderOptions, 'queries'> {
  queryClient?: QueryClient;
  router?: Router;
}

const Wrapper = ({
  children,
  queryClient,
}: {
  children: ReactElement;
  queryClient: QueryClient;
}): ReactElement => (
  <QueryClientProvider client={queryClient}>
    {children}
    <ReactQueryDevtools initialIsOpen={false} />
  </QueryClientProvider>
);

export function renderWithProviders(
  ui: ReactElement,
  {
    queryClient = createTestQueryClient(),
    ...renderOptions
  }: ExtendedRenderOptions = {},
) {
  return render(ui, {
    wrapper: (props) => <Wrapper {...props} queryClient={queryClient} />,
    ...renderOptions,
  });
}

// Re-export everything from React Testing Library
export * from '@testing-library/react';
export { renderWithProviders as render };
```

**Always import from test-utils:**

```typescript
// ❌ BAD: Direct RTL import
import { render } from '@testing-library/react';

// ✅ GOOD: From test-utils
import { render } from '@/test/test-utils';
```

---

## MSW v2 — API Mocking

### Handler Setup

**src/mocks/handlers.ts** — centralized API mocks:

```typescript
import { http, HttpResponse } from 'msw';

export const handlers = [
  http.get('/api/users/:id', ({ params }) => {
    const { id } = params as { id: string };
    return HttpResponse.json({ id, name: 'John Doe' });
  }),

  http.post('/api/auth/login', async ({ request }) => {
    const body = await request.json();
    if (body.email === 'test@example.com') {
      return HttpResponse.json(
        { token: 'mock-token', user: { id: '1', email: body.email } },
        { status: 200 }
      );
    }
    return HttpResponse.json(
      { error: 'Invalid credentials' },
      { status: 401 }
    );
  }),
];
```

### Server Setup

**src/mocks/server.ts** — Vitest integration:

```typescript
import { setupServer } from 'msw/node';
import { handlers } from './handlers';

export const server = setupServer(...handlers);
```

### Vitest Configuration

**vitest.config.ts:**

```typescript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      lines: 80,
      functions: 80,
      branches: 80,
      statements: 80,
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
});
```

**src/test/setup.ts:**

```typescript
import { cleanup } from '@testing-library/react';
import { afterAll, afterEach, beforeAll, vi } from 'vitest';
import { server } from '@/mocks/server';

// Enable API mocking before all tests
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));

// Reset handlers after each test
afterEach(() => {
  server.resetHandlers();
  cleanup();
});

// Disable API mocking after tests
afterAll(() => server.close());
```

### Per-Test API Overrides

Override handlers for specific tests:

```typescript
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';
import { describe, it, expect } from 'vitest';
import { render, screen } from '@/test/test-utils';
import { LoginForm } from './LoginForm';

describe('LoginForm', () => {
  it('shows error on failed login', async () => {
    // Override handler for this test
    server.use(
      http.post('/api/auth/login', () => {
        return HttpResponse.json(
          { error: 'Invalid credentials' },
          { status: 401 }
        );
      })
    );

    render(<LoginForm />);
    // ... test error state
  });
});
```

---

## Test Patterns

### Unit Test — Pure Function

```typescript
// formatDate.ts
export function formatDate(date: Date): string {
  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
}

// formatDate.test.ts
import { describe, it, expect } from 'vitest';
import { formatDate } from './formatDate';

describe('formatDate', () => {
  it('formats date correctly', () => {
    const date = new Date('2024-12-25');
    expect(formatDate(date)).toBe('December 25, 2024');
  });

  it('handles different dates', () => {
    expect(formatDate(new Date('2024-01-01'))).toBe('January 1, 2024');
  });
});
```

### Unit Test — Hook (without rendering)

```typescript
// useAuth.test.ts
import { describe, it, expect, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { useAuth } from './useAuth';

describe('useAuth', () => {
  it('returns null user on init', () => {
    const { result } = renderHook(() => useAuth());
    expect(result.current.user).toBeNull();
  });

  it('logs in user', async () => {
    const { result } = renderHook(() => useAuth());

    // Simulate login
    await waitFor(() => {
      result.current.login('test@example.com', 'password');
    });

    expect(result.current.user?.email).toBe('test@example.com');
  });
});
```

### Integration Test — Component with API

```typescript
// LoginForm.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@/test/test-utils';
import userEvent from '@testing-library/user-event';
import { LoginForm } from './LoginForm';

describe('LoginForm', () => {
  it('logs in user on valid credentials', async () => {
    const user = userEvent.setup();
    render(<LoginForm onSuccess={vi.fn()} />);

    // Find inputs by role
    const emailInput = screen.getByRole('textbox', { name: /email/i });
    const passwordInput = screen.getByLabelText(/password/i);
    const submitButton = screen.getByRole('button', { name: /sign in/i });

    // Simulate user interaction
    await user.type(emailInput, 'test@example.com');
    await user.type(passwordInput, 'password');
    await user.click(submitButton);

    // Wait for success state
    await waitFor(() => {
      expect(screen.getByText(/logged in/i)).toBeInTheDocument();
    });
  });

  it('shows error on invalid credentials', async () => {
    // Handler override from setup
    server.use(
      http.post('/api/auth/login', () =>
        HttpResponse.json({ error: 'Invalid' }, { status: 401 })
      )
    );

    const user = userEvent.setup();
    render(<LoginForm onSuccess={vi.fn()} />);

    await user.type(screen.getByRole('textbox', { name: /email/i }), 'wrong@example.com');
    await user.type(screen.getByLabelText(/password/i), 'wrong');
    await user.click(screen.getByRole('button', { name: /sign in/i }));

    await waitFor(() => {
      expect(screen.getByText(/invalid credentials/i)).toBeInTheDocument();
    });
  });
});
```

### Query Selectors — Priority

Use this priority for selecting elements:

1. **`screen.getByRole()`** — most semantic, encourages accessible code
2. **`screen.getByLabelText()`** — form inputs with labels
3. **`screen.getByPlaceholderText()`** — inputs with placeholders
4. **`screen.getByText()`** — last resort for non-interactive text
5. **`screen.getByTestId()`** — only when others impossible (rare)

**Example:**

```typescript
// ✅ GOOD: Using getByRole
screen.getByRole('button', { name: /submit/i });
screen.getByRole('textbox', { name: /email/i });
screen.getByRole('heading', { level: 1 });

// ⚠️ ACCEPTABLE: Using getByLabelText
screen.getByLabelText(/password/i);

// ❌ AVOID: Using getByText without strong reason
screen.getByText('Click me'); // Brittle, tests text not behavior

// ❌ AVOID: Using getByTestId
screen.getByTestId('submit-button'); // Tests implementation, not behavior
```

---

## E2E Testing with Playwright

### Page Object Model

**e2e/pages/LoginPage.ts:**

```typescript
import type { Page } from '@playwright/test';

export class LoginPage {
  constructor(private page: Page) {}

  async goto(): Promise<void> {
    await this.page.goto('/login');
  }

  async login(email: string, password: string): Promise<void> {
    await this.page.fill('input[type="email"]', email);
    await this.page.fill('input[type="password"]', password);
    await this.page.click('button[type="submit"]');
  }

  async hasError(): Promise<boolean> {
    return this.page.isVisible('[role="alert"]');
  }

  async isLoggedIn(): Promise<boolean> {
    return this.page.isVisible('[data-testid="user-menu"]');
  }
}
```

### E2E Test

**e2e/tests/auth.spec.ts:**

```typescript
import { test, expect } from '@playwright/test';
import { LoginPage } from '../pages/LoginPage';

test.describe('Auth Flow', () => {
  test('user can log in', async ({ page }) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login('test@example.com', 'password');
    expect(await loginPage.isLoggedIn()).toBe(true);
  });

  test('shows error on invalid credentials', async ({ page }) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login('wrong@example.com', 'wrong');
    expect(await loginPage.hasError()).toBe(true);
  });
});
```

### Playwright Configuration

**playwright.config.ts:**

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e/tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
  ],
});
```

---

## TDD Cycle (7 Steps)

1. **Write user story** — understand what user wants
2. **Generate test cases** — happy path, edge cases, error states
3. **Run tests** — MUST fail (Red phase)
4. **Implement minimal code** — just enough to pass (Green phase)
5. **Run tests** — MUST pass, all must pass
6. **Refactor** — improve code quality with confidence
7. **Verify coverage** — ensure >= 80%

---

## Quality Gates (MANDATORY — max 3 iterations each)

### Gate 1: TypeScript Strict Check

```bash
pnpm typecheck
```

No errors, no warnings. Zero `any`, `!`, `as` (except `as const`).

### Gate 2: Full Test Suite

```bash
pnpm test
```

All tests passing. Zero failures. Coverage >= 80%.

### Gate 3: Linting

```bash
pnpm lint
```

Zero warnings. Zero errors. Automatic fixes with `--fix` acceptable.

**If any gate fails after 3 attempts:** Record remaining failures and proceed.

---

## Coverage Requirements

- **Lines:** >= 80%
- **Functions:** >= 80%
- **Branches:** >= 80%
- **Statements:** >= 80%

Check coverage:

```bash
pnpm test --coverage
```

### Coverage Exclusions

Never exclude code from coverage. If coverage is hard to reach:
- Consider refactoring to make code more testable
- Add integration tests to reach branches
- Only skip error paths if truly unreachable

---

## Common Mistakes

### ❌ Testing Implementation Details

```typescript
// WRONG: Tests internal state
it('stores user in state', () => {
  render(<LoginForm />);
  expect(component.state.user).toBeDefined();
});

// CORRECT: Tests user-visible behavior
it('shows user name after login', async () => {
  const user = userEvent.setup();
  render(<LoginForm />);
  await user.type(...);
  expect(screen.getByText('John Doe')).toBeInTheDocument();
});
```

### ❌ Using fireEvent

```typescript
// WRONG: fireEvent doesn't simulate real user interactions
fireEvent.click(button);
fireEvent.change(input, { target: { value: 'text' } });

// CORRECT: userEvent simulates realistic interactions
await userEvent.click(button);
await userEvent.type(input, 'text');
```

### ❌ Shared Mutable State

```typescript
// WRONG: beforeEach mutates state shared across tests
let queryClient: QueryClient;
beforeEach(() => {
  queryClient = new QueryClient();
  // Tests might affect each other
});

// CORRECT: Create fresh state in each test
it('test 1', () => {
  const queryClient = new QueryClient();
  // ...
});
```

### ❌ Mocking with vi.mock()

```typescript
// WRONG: Mocking fetch directly
vi.mock('node-fetch');

// CORRECT: MSW handles API mocking
server.use(http.get('/api/users', () => HttpResponse.json([])));
```

---

## Summary

TDD ensures:
1. ✅ Tests written BEFORE implementation
2. ✅ Coverage >= 80% (real testing, not coverage gaming)
3. ✅ All tests passing before quality gates
4. ✅ API mocked with MSW (never vi.mock)
5. ✅ Testing user behavior, not implementation
6. ✅ Fast feedback loop: Red → Green → Refactor
