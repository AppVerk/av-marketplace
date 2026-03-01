---
name: tanstack-query-patterns
description: TanStack Query v5 server state management with queryOptions, mutations, caching, and error handling
---

# TanStack Query Patterns — Server State

## Overview

TanStack Query patterns for server state:
- `queryOptions` helper pattern
- Query key factories
- API service layer (pure functions)
- Axios interceptors
- Mutations with optimistic updates
- Global error handling
- Error boundaries
- Suspense integration

---

## Hard Rules

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- ALWAYS use `queryOptions` helper to define queries — single source of truth for queryKey + queryFn
- ALWAYS use query key factories — one source of truth per domain
- NEVER cache API responses in Zustand — TanStack Query IS the server state cache
- NEVER use `onSuccess` / `onError` on `useQuery` — removed in v5; use `QueryCache`/`MutationCache` callbacks
- ALWAYS set `retry: false` and `gcTime: 0` in test QueryClient
- ALWAYS invalidate after mutation — never manual cache update unless optimistic
- NEVER use raw `useEffect` + `fetch` for API calls — TanStack Query for EVERY API call
- ALWAYS define API functions as pure functions in the service layer
- ALWAYS use Axios with centralized interceptors for auth + error handling

</HARD-RULES>

---

## API Service Layer

### Axios Client

```typescript
// src/lib/api-client.ts
import axios from 'axios';
import type { AxiosError, InternalAxiosRequestConfig, AxiosResponse } from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:3000/api';

export const apiClient = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Auth interceptor — attach token to requests
apiClient.interceptors.request.use(
  (config: InternalAxiosRequestConfig): InternalAxiosRequestConfig => {
    const token = localStorage.getItem('auth-token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  }
);

// Error interceptor — handle 401/403 globally
apiClient.interceptors.response.use(
  (response: AxiosResponse): AxiosResponse => response,
  async (error: AxiosError): Promise<never> => {
    if (error.response?.status === 401) {
      localStorage.removeItem('auth-token');
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);
```

### Pure API Functions

```typescript
// src/features/users/api/usersApi.ts
import type { User, CreateUserInput, UpdateUserInput } from '../types';
import { apiClient } from '@/lib/api-client';

export async function fetchUsers(): Promise<User[]> {
  const response = await apiClient.get<User[]>('/users');
  return response.data;
}

export async function fetchUser(id: string): Promise<User> {
  const response = await apiClient.get<User>(`/users/${id}`);
  return response.data;
}

export async function createUser(input: CreateUserInput): Promise<User> {
  const response = await apiClient.post<User>('/users', input);
  return response.data;
}

export async function updateUser(id: string, input: UpdateUserInput): Promise<User> {
  const response = await apiClient.patch<User>(`/users/${id}`, input);
  return response.data;
}

export async function deleteUser(id: string): Promise<void> {
  await apiClient.delete(`/users/${id}`);
}
```

**Rules:**
- Pure functions — no React, no hooks, no side effects beyond the API call
- One file per domain: `usersApi.ts`, `ordersApi.ts`, `productsApi.ts`
- Located in `src/features/<name>/api/<name>Api.ts`
- Fully testable without rendering

---

## Query Key Factories

### Single Source of Truth

```typescript
// src/features/users/api/queries.ts
import { queryOptions } from '@tanstack/react-query';

import { fetchUser, fetchUsers } from './usersApi';

export const usersQueries = {
  all: () => queryOptions({
    queryKey: ['users'] as const,
    queryFn: fetchUsers,
  }),

  detail: (id: string) => queryOptions({
    queryKey: ['users', id] as const,
    queryFn: () => fetchUser(id),
  }),

  search: (query: string) => queryOptions({
    queryKey: ['users', 'search', query] as const,
    queryFn: () => searchUsers(query),
    enabled: query.length > 0,
  }),
};
```

### Usage in Components

```typescript
import { useQuery, useSuspenseQuery } from '@tanstack/react-query';
import { usersQueries } from '../api/queries';

// Standard query (loading/error states)
function UserList(): React.ReactElement {
  const { data: users, isLoading, error } = useQuery(usersQueries.all());

  if (isLoading) return <Spinner />;
  if (error) return <ErrorMessage error={error} />;

  return (
    <ul>
      {users?.map((user) => (
        <li key={user.id}>{user.name}</li>
      ))}
    </ul>
  );
}

// Suspense query (data guaranteed at render)
function UserDetail({ userId }: { userId: string }): React.ReactElement {
  const { data: user } = useSuspenseQuery(usersQueries.detail(userId));

  // user is never undefined — Suspense handles loading
  return <div>{user.name}</div>;
}
```

### Usage in Route Loaders

```typescript
// With TanStack Router loader
import { usersQueries } from '@/features/users/api/queries';

export const Route = createFileRoute('/users/$userId')({
  loader: ({ context: { queryClient }, params: { userId } }) =>
    queryClient.ensureQueryData(usersQueries.detail(userId)),
  component: UserDetailPage,
});

function UserDetailPage(): React.ReactElement {
  const { userId } = Route.useParams();
  // Data already cached by loader
  const { data: user } = useSuspenseQuery(usersQueries.detail(userId));
  return <UserProfile user={user} />;
}
```

---

## Query Client Setup

```typescript
// src/lib/query-client.ts
import { QueryClient, QueryCache, MutationCache } from '@tanstack/react-query';
import { toast } from 'sonner';

export const queryClient = new QueryClient({
  queryCache: new QueryCache({
    onError: (error, query) => {
      // Only show toast for background refetch errors
      if (query.state.data !== undefined) {
        toast.error(`Background update failed: ${error.message}`);
      }
    },
  }),
  mutationCache: new MutationCache({
    onError: (error) => {
      toast.error(`Operation failed: ${error.message}`);
    },
  }),
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60, // 1 minute
      gcTime: 1000 * 60 * 5, // 5 minutes
      refetchOnWindowFocus: false,
      retry: 1,
    },
    mutations: {
      retry: false,
    },
  },
});
```

### Test QueryClient

```typescript
// src/test/test-utils.tsx
export function createTestQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,      // No retries in tests
        gcTime: 0,         // No caching in tests
      },
      mutations: {
        retry: false,
      },
    },
  });
}
```

---

## Mutations

### Basic Mutation with Invalidation

```typescript
// src/features/users/hooks/useCreateUser.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';

import { createUser } from '../api/usersApi';
import type { CreateUserInput } from '../types';

export function useCreateUser() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (input: CreateUserInput) => createUser(input),
    onSuccess: () => {
      // Invalidate the users list to refetch
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
  });
}
```

### Usage in Component

```typescript
function CreateUserForm(): React.ReactElement {
  const createUser = useCreateUser();

  function handleSubmit(data: CreateUserInput): void {
    createUser.mutate(data, {
      onSuccess: () => {
        toast.success('User created');
      },
    });
  }

  return (
    <form onSubmit={handleFormSubmit(handleSubmit)}>
      {/* form fields */}
      <Button disabled={createUser.isPending}>
        {createUser.isPending ? 'Creating...' : 'Create User'}
      </Button>
    </form>
  );
}
```

### Optimistic Updates

```typescript
// src/features/todos/hooks/useToggleTodo.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';

import { toggleTodo } from '../api/todosApi';
import type { Todo } from '../types';

export function useToggleTodo() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => toggleTodo(id),

    onMutate: async (id: string) => {
      // 1. Cancel outgoing refetches
      await queryClient.cancelQueries({ queryKey: ['todos'] });

      // 2. Snapshot previous value
      const previousTodos = queryClient.getQueryData<Todo[]>(['todos']);

      // 3. Optimistically update
      queryClient.setQueryData<Todo[]>(['todos'], (old) =>
        old?.map((todo) =>
          todo.id === id ? { ...todo, done: !todo.done } : todo
        )
      );

      // 4. Return snapshot for rollback
      return { previousTodos };
    },

    onError: (_error, _id, context) => {
      // Rollback on error
      if (context?.previousTodos) {
        queryClient.setQueryData(['todos'], context.previousTodos);
      }
    },

    onSettled: () => {
      // Always refetch after mutation to sync with server
      queryClient.invalidateQueries({ queryKey: ['todos'] });
    },
  });
}
```

---

## Error Handling

### Four-Layer Error Strategy

**Layer 1: Axios Interceptors** — Global transport errors (401, 403, network)

```typescript
// Already defined in api-client.ts — handles auth redirect
apiClient.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    if (error.response?.status === 401) {
      // redirect to login
    }
    return Promise.reject(error);
  }
);
```

**Layer 2: QueryCache/MutationCache** — Global toast notifications

```typescript
// Already defined in query-client.ts
new QueryCache({
  onError: (error, query) => {
    if (query.state.data !== undefined) {
      toast.error(`Background update failed: ${error.message}`);
    }
  },
});
```

**Layer 3: Error Boundaries** — Catch rendering errors gracefully

```typescript
import { QueryErrorResetBoundary } from '@tanstack/react-query';
import { ErrorBoundary } from 'react-error-boundary';

function ErrorFallback({
  error,
  resetErrorBoundary,
}: {
  error: Error;
  resetErrorBoundary: () => void;
}): React.ReactElement {
  return (
    <div role="alert" className="rounded-lg border border-destructive p-4">
      <h2 className="text-lg font-semibold">Something went wrong</h2>
      <p className="text-sm text-muted-foreground">{error.message}</p>
      <Button variant="outline" onClick={resetErrorBoundary}>
        Try again
      </Button>
    </div>
  );
}

// Wrap sections of the app
function UserSection(): React.ReactElement {
  return (
    <QueryErrorResetBoundary>
      {({ reset }) => (
        <ErrorBoundary onReset={reset} FallbackComponent={ErrorFallback}>
          <Suspense fallback={<Spinner />}>
            <UserList />
          </Suspense>
        </ErrorBoundary>
      )}
    </QueryErrorResetBoundary>
  );
}
```

**Layer 4: Component-Level** — Specific error UI per query

```typescript
function UserList(): React.ReactElement {
  const { data: users, error, isLoading } = useQuery(usersQueries.all());

  if (isLoading) return <UserListSkeleton />;
  if (error) return <Alert variant="destructive">Failed to load users: {error.message}</Alert>;

  return <ul>{users?.map(renderUser)}</ul>;
}
```

---

## Suspense Integration

### `useSuspenseQuery` — Guaranteed Data

```typescript
import { useSuspenseQuery } from '@tanstack/react-query';
import { Suspense } from 'react';

// Component — data is NEVER undefined
function UserProfile({ userId }: { userId: string }): React.ReactElement {
  const { data: user } = useSuspenseQuery(usersQueries.detail(userId));
  // user is guaranteed non-null — no loading/error checks needed
  return (
    <div>
      <h1>{user.name}</h1>
      <p>{user.email}</p>
    </div>
  );
}

// Parent wraps with Suspense + Error Boundary
function UserPage({ userId }: { userId: string }): React.ReactElement {
  return (
    <QueryErrorResetBoundary>
      {({ reset }) => (
        <ErrorBoundary onReset={reset} FallbackComponent={ErrorFallback}>
          <Suspense fallback={<UserProfileSkeleton />}>
            <UserProfile userId={userId} />
          </Suspense>
        </ErrorBoundary>
      )}
    </QueryErrorResetBoundary>
  );
}
```

---

## Invalidation Strategies

### After Mutations

```typescript
// Invalidate specific query
queryClient.invalidateQueries({ queryKey: ['users', userId] });

// Invalidate all queries starting with 'users'
queryClient.invalidateQueries({ queryKey: ['users'] });

// Invalidate everything (rare, use sparingly)
queryClient.invalidateQueries();
```

### Dependent Query Invalidation

```typescript
// When updating a user, invalidate both user detail and user list
onSuccess: (updatedUser) => {
  queryClient.invalidateQueries({ queryKey: ['users'] }); // list
  queryClient.invalidateQueries({ queryKey: ['users', updatedUser.id] }); // detail
},
```

### Prefetching

```typescript
// Prefetch on hover (e.g., link hover)
function UserLink({ userId }: { userId: string }): React.ReactElement {
  const queryClient = useQueryClient();

  function handleMouseEnter(): void {
    queryClient.prefetchQuery(usersQueries.detail(userId));
  }

  return (
    <Link
      to="/users/$userId"
      params={{ userId }}
      onMouseEnter={handleMouseEnter}
    >
      View User
    </Link>
  );
}
```

---

## Testing Queries

### Testing Components with Queries

```typescript
import { describe, it, expect } from 'vitest';
import { render, screen, waitFor } from '@/test/test-utils';
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';
import { UserList } from './UserList';

describe('UserList', () => {
  it('renders users from API', async () => {
    server.use(
      http.get('/api/users', () =>
        HttpResponse.json([
          { id: '1', name: 'Alice', email: 'alice@example.com' },
          { id: '2', name: 'Bob', email: 'bob@example.com' },
        ])
      )
    );

    render(<UserList />);

    await waitFor(() => {
      expect(screen.getByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();
    });
  });

  it('shows error state on API failure', async () => {
    server.use(
      http.get('/api/users', () =>
        HttpResponse.json({ error: 'Server error' }, { status: 500 })
      )
    );

    render(<UserList />);

    await waitFor(() => {
      expect(screen.getByRole('alert')).toBeInTheDocument();
    });
  });
});
```

### Testing Mutations

```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@/test/test-utils';
import userEvent from '@testing-library/user-event';
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';
import { CreateUserForm } from './CreateUserForm';

describe('CreateUserForm', () => {
  it('creates user and shows success', async () => {
    const user = userEvent.setup();
    server.use(
      http.post('/api/users', async ({ request }) => {
        const body = await request.json();
        return HttpResponse.json({ id: '3', ...body }, { status: 201 });
      })
    );

    render(<CreateUserForm />);

    await user.type(screen.getByRole('textbox', { name: /name/i }), 'Charlie');
    await user.type(screen.getByRole('textbox', { name: /email/i }), 'charlie@example.com');
    await user.click(screen.getByRole('button', { name: /create/i }));

    await waitFor(() => {
      expect(screen.getByText(/user created/i)).toBeInTheDocument();
    });
  });
});
```

---

## Common Mistakes

### ❌ Caching API Data in Zustand

```typescript
// WRONG: Duplicating server state in Zustand
const useStore = create((set) => ({
  users: [],
  fetchUsers: async () => {
    const users = await api.getUsers();
    set({ users });
  },
}));

// CORRECT: Let TanStack Query manage server state
const { data: users } = useQuery(usersQueries.all());
```

### ❌ Using useEffect + fetch

```typescript
// WRONG: Manual data fetching
function UserList() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    fetch('/api/users').then(r => r.json()).then(setUsers).finally(() => setLoading(false));
  }, []);
}

// CORRECT: TanStack Query handles everything
function UserList() {
  const { data: users, isLoading } = useQuery(usersQueries.all());
}
```

### ❌ Using onSuccess on useQuery

```typescript
// WRONG: onSuccess removed in v5
const { data } = useQuery({
  queryKey: ['users'],
  queryFn: fetchUsers,
  onSuccess: (data) => doSomething(data), // Does not exist in v5
});

// CORRECT: Use useEffect or handle in QueryCache
const { data } = useQuery(usersQueries.all());
useEffect(() => {
  if (data) doSomething(data);
}, [data]);
```

---

## Summary

1. ✅ `queryOptions` for every query definition
2. ✅ Query key factories — one source of truth per domain
3. ✅ Pure API service functions in `features/<name>/api/`
4. ✅ Axios client with auth + error interceptors
5. ✅ Mutations with invalidation (or optimistic updates)
6. ✅ Four-layer error handling (interceptors, cache, boundaries, component)
7. ✅ Suspense for guaranteed data at render time
8. ✅ MSW for API mocking in tests
