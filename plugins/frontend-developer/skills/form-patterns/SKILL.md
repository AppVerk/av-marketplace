---
name: form-patterns
description: React Hook Form with Zod validation, server-side error handling, mutation integration, and reusable form components
---

# Form Patterns — React Hook Form + Zod

## Overview

Form handling patterns for React Hook Form + Zod:
- Zod schemas as single source of truth for types
- zodResolver integration
- Server-side error mapping
- Mutation integration with isPending
- Reusable form field components
- Schema composition and derivation
- Testing forms (validation, submit, server errors)

---

## Hard Rules

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- ALWAYS use Zod schema as single source of truth: `type FormData = z.infer<typeof schema>`
- ALWAYS use `zodResolver` to connect Zod with React Hook Form
- ALWAYS use `z.coerce.number()` for numeric inputs — HTML inputs return strings
- NEVER use Formik in new code — React Hook Form is the standard
- NEVER use controlled inputs without need — RHF defaults to uncontrolled for performance
- ALWAYS map server-side errors to fields via `setError`
- ALWAYS block submit with mutation `isPending` — prevent double submissions
- ALWAYS define one schema per form — NEVER create a universal mega-schema
- NEVER use `any` in form types — derive everything from Zod schemas
- ALWAYS handle loading, error, and success states in form submission

</HARD-RULES>

---

## Zod Schemas — Single Source of Truth

### Why Zod?

Zod schemas define validation AND TypeScript types in one place. No type drift between frontend validation and TypeScript interfaces.

```typescript
// ❌ BAD: Separate type and validation — they can drift apart
interface UserForm {
  name: string;
  email: string;
  age: number;
}

const validate = (data: UserForm) => {
  if (!data.name) return { name: 'Required' };
  // ...manual validation
};

// ✅ GOOD: Zod schema is the single source of truth
import { z } from 'zod';

const createUserSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100, 'Name too long'),
  email: z.string().email('Invalid email address'),
  age: z.coerce.number().min(18, 'Must be 18 or older').max(150, 'Invalid age'),
});

// Type is derived — always in sync with validation
type CreateUserForm = z.infer<typeof createUserSchema>;
// Result: { name: string; email: string; age: number }
```

### Schema Location

```
src/features/users/
  schemas/
    createUserSchema.ts    # Create form schema
    updateUserSchema.ts    # Update form schema (derived)
  components/
    CreateUserForm.tsx
    EditUserForm.tsx
```

### Schema Per-Form, Not Mega-Schema

```typescript
// ❌ BAD: One schema for all forms
const userSchema = z.object({
  name: z.string(),
  email: z.string().email(),
  age: z.coerce.number(),
  role: z.enum(['admin', 'user']),        // Only needed in admin form
  password: z.string().min(8),            // Only needed in registration
  confirmPassword: z.string(),            // Only needed in registration
  bio: z.string().optional(),             // Only needed in profile form
});

// ✅ GOOD: One schema per form
const registrationSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  email: z.string().email('Invalid email'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
  confirmPassword: z.string(),
}).refine((data) => data.password === data.confirmPassword, {
  message: 'Passwords do not match',
  path: ['confirmPassword'],
});

const profileSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  bio: z.string().max(500, 'Bio too long').optional(),
});
```

### Derived Schemas

```typescript
// Create schema — all fields required
const createUserSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  email: z.string().email('Invalid email'),
  role: z.enum(['admin', 'user', 'viewer']),
});

type CreateUserForm = z.infer<typeof createUserSchema>;

// Update schema — derived from create, all optional except id
const updateUserSchema = createUserSchema.partial().extend({
  id: z.string().uuid(),
});

type UpdateUserForm = z.infer<typeof updateUserSchema>;
// Result: { id: string; name?: string; email?: string; role?: 'admin' | 'user' | 'viewer' }
```

### Common Zod Patterns

```typescript
// Numeric inputs — ALWAYS use z.coerce for HTML inputs
const schema = z.object({
  quantity: z.coerce.number().int().positive('Must be positive'),
  price: z.coerce.number().min(0, 'Price cannot be negative'),
});

// Optional with default
const schema = z.object({
  role: z.enum(['user', 'admin']).default('user'),
  notifications: z.boolean().default(true),
});

// Conditional validation with refine
const schema = z.object({
  hasDiscount: z.boolean(),
  discountCode: z.string().optional(),
}).refine(
  (data) => !data.hasDiscount || (data.discountCode && data.discountCode.length > 0),
  {
    message: 'Discount code is required when discount is enabled',
    path: ['discountCode'],
  }
);

// Enum from const object (matches coding-standards — no TypeScript enum)
const ROLES = {
  Admin: 'admin',
  User: 'user',
  Viewer: 'viewer',
} as const;

type Role = (typeof ROLES)[keyof typeof ROLES];

const schema = z.object({
  role: z.enum(['admin', 'user', 'viewer']),
});
```

---

## Form Component Setup

### Basic Form with useForm + zodResolver

```typescript
// src/features/users/components/CreateUserForm.tsx
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

import { Button } from '@/components/ui/button';
import { useCreateUser } from '@/features/users/hooks/useCreateUser';

const createUserSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100),
  email: z.string().email('Invalid email address'),
  age: z.coerce.number().min(18, 'Must be 18 or older'),
});

type CreateUserForm = z.infer<typeof createUserSchema>;

function CreateUserForm(): React.ReactElement {
  const createUser = useCreateUser();

  const {
    register,
    handleSubmit,
    setError,
    formState: { errors, isSubmitting },
  } = useForm<CreateUserForm>({
    resolver: zodResolver(createUserSchema),
    defaultValues: {
      name: '',
      email: '',
      age: 18,
    },
  });

  const onSubmit = async (data: CreateUserForm): Promise<void> => {
    try {
      await createUser.mutateAsync(data);
    } catch (error: unknown) {
      // Map server-side errors to form fields
      if (isValidationError(error)) {
        for (const fieldError of error.fieldErrors) {
          setError(fieldError.field as keyof CreateUserForm, {
            message: fieldError.message,
          });
        }
        return;
      }
      // Non-field error — set on root
      setError('root', { message: 'Failed to create user. Please try again.' });
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      <div>
        <label htmlFor="name">Name</label>
        <input id="name" {...register('name')} aria-invalid={!!errors.name} />
        {errors.name ? <p role="alert">{errors.name.message}</p> : null}
      </div>

      <div>
        <label htmlFor="email">Email</label>
        <input id="email" type="email" {...register('email')} aria-invalid={!!errors.email} />
        {errors.email ? <p role="alert">{errors.email.message}</p> : null}
      </div>

      <div>
        <label htmlFor="age">Age</label>
        <input id="age" type="number" {...register('age')} aria-invalid={!!errors.age} />
        {errors.age ? <p role="alert">{errors.age.message}</p> : null}
      </div>

      {errors.root ? <p role="alert">{errors.root.message}</p> : null}

      <Button type="submit" disabled={createUser.isPending || isSubmitting}>
        {createUser.isPending ? 'Creating...' : 'Create User'}
      </Button>
    </form>
  );
}
```

### Mutation Hook Integration

```typescript
// src/features/users/hooks/useCreateUser.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';

import type { CreateUserPayload, User } from '@/features/users/types';
import { createUser } from '@/features/users/api/usersApi';
import { usersQueries } from '@/features/users/api/queries';

export function useCreateUser(): UseMutationResult<User, Error, CreateUserPayload> {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: createUser,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: usersQueries.all().queryKey });
    },
  });
}
```

---

## Server-Side Error Handling

### Error Response Shape

```typescript
// src/types/api-error.ts
interface ValidationError {
  status: 422;
  fieldErrors: Array<{
    field: string;
    message: string;
  }>;
}

function isValidationError(error: unknown): error is ValidationError {
  return (
    typeof error === 'object' &&
    error !== null &&
    'status' in error &&
    (error as Record<string, unknown>).status === 422 &&
    'fieldErrors' in error &&
    Array.isArray((error as Record<string, unknown>).fieldErrors)
  );
}
```

### Mapping Server Errors to Fields

```typescript
const onSubmit = async (data: CreateUserForm): Promise<void> => {
  try {
    await createUser.mutateAsync(data);
  } catch (error: unknown) {
    if (isValidationError(error)) {
      // Map each server field error to the corresponding form field
      for (const fieldError of error.fieldErrors) {
        setError(fieldError.field as keyof CreateUserForm, {
          type: 'server',
          message: fieldError.message,
        });
      }
      return;
    }

    // Generic error — not tied to a specific field
    setError('root', {
      message: 'Something went wrong. Please try again.',
    });
  }
};
```

---

## Reusable FormField Component

### FormField Wrapper

```typescript
// src/components/ui/form-field.tsx
import type { FieldError } from 'react-hook-form';

interface FormFieldProps {
  label: string;
  htmlFor: string;
  error?: FieldError;
  required?: boolean;
  children: React.ReactNode;
}

function FormField({ label, htmlFor, error, required, children }: FormFieldProps): React.ReactElement {
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={htmlFor} className="text-sm font-medium">
        {label}
        {required ? <span className="text-destructive ml-1" aria-hidden="true">*</span> : null}
      </label>
      {children}
      {error ? (
        <p role="alert" className="text-sm text-destructive">
          {error.message}
        </p>
      ) : null}
    </div>
  );
}
```

### Usage with Register

```typescript
function CreateUserForm(): React.ReactElement {
  const { register, handleSubmit, formState: { errors } } = useForm<CreateUserForm>({
    resolver: zodResolver(createUserSchema),
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      <FormField label="Name" htmlFor="name" error={errors.name} required>
        <input
          id="name"
          {...register('name')}
          aria-invalid={!!errors.name}
          className="rounded-md border px-3 py-2"
        />
      </FormField>

      <FormField label="Email" htmlFor="email" error={errors.email} required>
        <input
          id="email"
          type="email"
          {...register('email')}
          aria-invalid={!!errors.email}
          className="rounded-md border px-3 py-2"
        />
      </FormField>

      <Button type="submit" disabled={isSubmitting}>Submit</Button>
    </form>
  );
}
```

---

## Advanced Patterns

### Multi-Step Form

```typescript
// Track step in component state, validate step-by-step
const STEPS = ['personal', 'contact', 'review'] as const;
type Step = (typeof STEPS)[number];

function MultiStepForm(): React.ReactElement {
  const [step, setStep] = useState<Step>('personal');

  const form = useForm<FullFormData>({
    resolver: zodResolver(fullFormSchema),
    mode: 'onTouched', // Validate on blur for multi-step
  });

  const goToNext = async (): Promise<void> => {
    // Validate only current step's fields
    const fieldsToValidate = STEP_FIELDS[step];
    const isValid = await form.trigger(fieldsToValidate);
    if (isValid) {
      const currentIndex = STEPS.indexOf(step);
      const nextStep = STEPS[currentIndex + 1];
      if (nextStep) {
        setStep(nextStep);
      }
    }
  };

  return (
    <form onSubmit={form.handleSubmit(onSubmit)}>
      {step === 'personal' ? <PersonalStep form={form} /> : null}
      {step === 'contact' ? <ContactStep form={form} /> : null}
      {step === 'review' ? <ReviewStep form={form} /> : null}

      <div className="flex gap-2">
        {step !== 'personal' ? (
          <Button type="button" variant="secondary" onClick={goToPrev}>
            Back
          </Button>
        ) : null}
        {step !== 'review' ? (
          <Button type="button" onClick={goToNext}>Next</Button>
        ) : (
          <Button type="submit" disabled={form.formState.isSubmitting}>Submit</Button>
        )}
      </div>
    </form>
  );
}
```

### Dynamic Field Arrays

```typescript
import { useFieldArray, useForm } from 'react-hook-form';

const teamSchema = z.object({
  teamName: z.string().min(1),
  members: z.array(
    z.object({
      name: z.string().min(1, 'Member name is required'),
      role: z.enum(['lead', 'member', 'observer']),
    })
  ).min(1, 'At least one member is required'),
});

type TeamForm = z.infer<typeof teamSchema>;

function TeamForm(): React.ReactElement {
  const { register, control, handleSubmit, formState: { errors } } = useForm<TeamForm>({
    resolver: zodResolver(teamSchema),
    defaultValues: {
      teamName: '',
      members: [{ name: '', role: 'member' }],
    },
  });

  const { fields, append, remove } = useFieldArray({
    control,
    name: 'members',
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input {...register('teamName')} />

      {fields.map((field, index) => (
        <div key={field.id}>
          <input {...register(`members.${index}.name`)} />
          {errors.members?.[index]?.name ? (
            <p role="alert">{errors.members[index].name.message}</p>
          ) : null}

          <select {...register(`members.${index}.role`)}>
            <option value="lead">Lead</option>
            <option value="member">Member</option>
            <option value="observer">Observer</option>
          </select>

          <Button type="button" onClick={() => remove(index)}>Remove</Button>
        </div>
      ))}

      <Button type="button" onClick={() => append({ name: '', role: 'member' })}>
        Add Member
      </Button>

      <Button type="submit">Save Team</Button>
    </form>
  );
}
```

---

## Testing Forms

### Testing Validation Errors

```typescript
import { describe, it, expect } from 'vitest';
import { render, screen } from '@/test/test-utils';
import userEvent from '@testing-library/user-event';
import { CreateUserForm } from './CreateUserForm';

describe('CreateUserForm', () => {
  it('shows validation errors for empty required fields', async () => {
    const user = userEvent.setup();
    render(<CreateUserForm />);

    await user.click(screen.getByRole('button', { name: /create user/i }));

    expect(await screen.findByText('Name is required')).toBeInTheDocument();
    expect(await screen.findByText('Invalid email address')).toBeInTheDocument();
  });

  it('shows validation error for invalid email', async () => {
    const user = userEvent.setup();
    render(<CreateUserForm />);

    await user.type(screen.getByRole('textbox', { name: /email/i }), 'not-an-email');
    await user.click(screen.getByRole('button', { name: /create user/i }));

    expect(await screen.findByText('Invalid email address')).toBeInTheDocument();
  });

  it('shows validation error for age under 18', async () => {
    const user = userEvent.setup();
    render(<CreateUserForm />);

    const ageInput = screen.getByRole('spinbutton', { name: /age/i });
    await user.clear(ageInput);
    await user.type(ageInput, '15');
    await user.click(screen.getByRole('button', { name: /create user/i }));

    expect(await screen.findByText('Must be 18 or older')).toBeInTheDocument();
  });
});
```

### Testing Successful Submission

```typescript
import { http, HttpResponse } from 'msw';
import { server } from '@/mocks/server';

describe('CreateUserForm — submission', () => {
  it('submits form with valid data', async () => {
    const user = userEvent.setup();
    render(<CreateUserForm />);

    await user.type(screen.getByRole('textbox', { name: /name/i }), 'Jane Doe');
    await user.type(screen.getByRole('textbox', { name: /email/i }), 'jane@example.com');

    const ageInput = screen.getByRole('spinbutton', { name: /age/i });
    await user.clear(ageInput);
    await user.type(ageInput, '25');

    await user.click(screen.getByRole('button', { name: /create user/i }));

    // Button shows loading state
    expect(screen.getByRole('button', { name: /creating/i })).toBeDisabled();

    // Success feedback (depends on your implementation)
    await screen.findByText(/user created/i);
  });

  it('disables submit button while mutation is pending', async () => {
    const user = userEvent.setup();
    render(<CreateUserForm />);

    await user.type(screen.getByRole('textbox', { name: /name/i }), 'Jane');
    await user.type(screen.getByRole('textbox', { name: /email/i }), 'jane@example.com');

    await user.click(screen.getByRole('button', { name: /create user/i }));

    expect(screen.getByRole('button', { name: /creating/i })).toBeDisabled();
  });
});
```

### Testing Server-Side Field Errors

```typescript
describe('CreateUserForm — server errors', () => {
  it('displays server-side field errors', async () => {
    // Override MSW handler for this test
    server.use(
      http.post('/api/users', () => {
        return HttpResponse.json(
          {
            status: 422,
            fieldErrors: [
              { field: 'email', message: 'Email already exists' },
            ],
          },
          { status: 422 }
        );
      })
    );

    const user = userEvent.setup();
    render(<CreateUserForm />);

    await user.type(screen.getByRole('textbox', { name: /name/i }), 'Jane');
    await user.type(screen.getByRole('textbox', { name: /email/i }), 'taken@example.com');

    const ageInput = screen.getByRole('spinbutton', { name: /age/i });
    await user.clear(ageInput);
    await user.type(ageInput, '25');

    await user.click(screen.getByRole('button', { name: /create user/i }));

    expect(await screen.findByText('Email already exists')).toBeInTheDocument();
  });

  it('displays generic error for non-validation failures', async () => {
    server.use(
      http.post('/api/users', () => {
        return HttpResponse.json(
          { message: 'Internal server error' },
          { status: 500 }
        );
      })
    );

    const user = userEvent.setup();
    render(<CreateUserForm />);

    await user.type(screen.getByRole('textbox', { name: /name/i }), 'Jane');
    await user.type(screen.getByRole('textbox', { name: /email/i }), 'jane@example.com');

    const ageInput = screen.getByRole('spinbutton', { name: /age/i });
    await user.clear(ageInput);
    await user.type(ageInput, '25');

    await user.click(screen.getByRole('button', { name: /create user/i }));

    expect(await screen.findByText(/failed to create user/i)).toBeInTheDocument();
  });
});
```

---

## Common Mistakes

### ❌ Manual Validation Instead of Zod

```typescript
// WRONG: Manual validation — duplicates types, error-prone
const validate = (values: FormValues) => {
  const errors: Record<string, string> = {};
  if (!values.email.includes('@')) errors.email = 'Invalid email';
  return errors;
};

// CORRECT: Zod schema validates and generates types
const schema = z.object({
  email: z.string().email('Invalid email'),
});
type FormValues = z.infer<typeof schema>;
```

### ❌ Not Blocking Double Submit

```typescript
// WRONG: No submit protection
<button type="submit">Submit</button>

// CORRECT: Block submit while mutation is pending
<Button type="submit" disabled={mutation.isPending || isSubmitting}>
  {mutation.isPending ? 'Submitting...' : 'Submit'}
</Button>
```

### ❌ Ignoring Server Errors

```typescript
// WRONG: Swallowing errors
const onSubmit = async (data: FormData): Promise<void> => {
  await mutation.mutateAsync(data); // Error goes to void
};

// CORRECT: Map server errors to form fields
const onSubmit = async (data: FormData): Promise<void> => {
  try {
    await mutation.mutateAsync(data);
  } catch (error: unknown) {
    if (isValidationError(error)) {
      for (const fieldError of error.fieldErrors) {
        setError(fieldError.field as keyof FormData, {
          message: fieldError.message,
        });
      }
      return;
    }
    setError('root', { message: 'Something went wrong' });
  }
};
```

### ❌ String Type for Number Inputs

```typescript
// WRONG: HTML input returns string, schema expects number
const schema = z.object({ age: z.number() });
// Will fail: "Expected number, received string"

// CORRECT: Use z.coerce to handle HTML input strings
const schema = z.object({ age: z.coerce.number().min(0) });
```

---

## Summary

1. ✅ Zod schema = single source of truth for validation AND types
2. ✅ `zodResolver` connects Zod to React Hook Form
3. ✅ `z.coerce.number()` for numeric HTML inputs
4. ✅ One schema per form, derived schemas via `.partial()` / `.omit()`
5. ✅ Server errors mapped to fields via `setError`
6. ✅ Submit blocked with `isPending` — no double submissions
7. ✅ Reusable `FormField` for label + error display
8. ✅ Test validation errors, successful submit, and server errors
