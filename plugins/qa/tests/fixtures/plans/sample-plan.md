# Test Plan: account profiles and document ownership

## Source
- Type: branch feature/profiles
- Branch: feature/profiles
- Head: 0123456789abcdef0123456789abcdef01234567

## Blockers / Findings
None found.

## Users
- user: registered — document owner
- other: registered — second plain user

## FE Test Scenarios

### FE-01: Sign in and display the owner's document
- **Target:** ui
- **Writes:** yes
- **Preconditions:** POST http://127.0.0.1:54321/auth/v1/signup with email `qa+$QA_TAG-user@test.local` and password `$QA_NEW_PASSWORD`; keep the token in the tester's session, then POST /api/v1/documents as that user.
- **Steps:**
  1. Open http://localhost:5173/login.
  2. Fill Email with `qa+$QA_TAG-user@test.local` and Password with `$QA_NEW_PASSWORD`.
  3. Open the newly created document.
- **Expected:** The owner can view the document title. (src/pages/document.tsx:101)
- **Edge cases:**
  - Missing password: validation keeps the login form open. (src/pages/login.tsx:88)
  - Other user `qa+$QA_TAG-other@test.local`: the document is not listed. (src/pages/document.tsx:109)

## BE Test Scenarios

### BE-01: Create an authenticated document
- **Target:** backend
- **Writes:** yes
- **Method:** POST /api/v1/documents
- **Preconditions:** POST http://127.0.0.1:54321/auth/v1/signup with email `qa+$QA_TAG-user@test.local` and password `$QA_NEW_PASSWORD`; keep the token in the tester's session and the returned id as `$QA_USER_ID`.
- **Payload:** `{"title":"QA document","owner":"$QA_USER_ID"}`
- **Expected:** 201, the response includes an id and title. (src/api/documents.py:201)
- **State Check:** supabase: `SELECT COUNT(id) FROM documents WHERE owner_id = '$QA_USER_ID'` → 1
- **State Check:** supabase: `SELECT COUNT(id) FROM storage.objects WHERE name LIKE '$QA_USER_ID/%'` → 0
- **Edge cases:**
  - Missing title: 422 with a validation error. (src/api/documents.py:422)
  - No Authorization header: 401. (src/api/auth.py:401)

### BE-02: Access another user's profile
- **Target:** supabase
- **Writes:** yes
- **Method:** GET http://127.0.0.1:54321/auth/v1/user
- **Headers:** apikey: $QA_SUPABASE_ANON_KEY; Authorization: Bearer the token captured in the tester's session.
- **Preconditions:** POST http://127.0.0.1:54321/auth/v1/signup with email `qa+$QA_TAG-other@test.local` and password `$QA_NEW_PASSWORD`; keep the token in the tester's session.
- **Expected:** 200, the returned profile belongs to the other user. (src/auth/profile.py:200)
- **Edge cases:**
  - No token: 401. (src/auth/profile.py:401)
  - Malformed token: 403. (src/auth/profile.py:403)
