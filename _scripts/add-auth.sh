#!/usr/bin/env bash
#
# add-auth.sh — scaffold per-user email/password auth into a Next.js app.
#
# WHAT IT DOES (fully automatic):
#   - installs jose + bcryptjs
#   - generates AUTH_SECRET and writes it to .env.local (+ .env.local.example)
#   - drops in app-agnostic auth files:
#       lib/auth.ts                 session create/read/delete + requireAuth()
#       lib/actions/auth.ts         register / login / logout / changePassword
#       proxy.ts                    route guard (redirects to /login)
#       app/login/page.tsx
#       app/register/page.tsx
#       app/account/page.tsx        change-password form
#   - never overwrites a file that already exists (prints a [skip] line instead)
#
# WHAT YOU STILL DO BY HAND (printed as a checklist at the end), because it
# depends on YOUR schema:
#   1. add a `users` table + a `userId` column to every per-user table
#   2. put requireAuth() at the top of each server action and scope its queries
#   3. run the DB migration (preserving existing rows under '__legacy__')
#   4. set AUTH_SECRET in Vercel and redeploy
#   5. claim your existing data with an UPDATE
#
# WHEN *NOT* TO USE THIS:
#   - Pure localStorage apps (Amex Credits, finance-tracker, PGA, etc.) are
#     ALREADY private — data lives in each visitor's browser, nobody sees yours.
#     You only need auth if you want a shared server-side datastore (a DB, or
#     Vercel KV) AND want each person's slice kept separate.
#   - Stack must be Next.js App Router + Server Actions. (Flask / vanilla-HTML
#     apps need a different approach entirely.)
#
# USAGE:
#   ./add-auth.sh [path-to-nextjs-app]      # defaults to current directory
#
set -euo pipefail

APP_DIR="${1:-$PWD}"
export PATH="/opt/homebrew/bin:$PATH"   # homebrew node isn't on $PATH by default

cd "$APP_DIR"

if [ ! -f package.json ] || ! grep -q '"next"' package.json; then
  echo "✗ $APP_DIR doesn't look like a Next.js app (no \"next\" in package.json)." >&2
  exit 1
fi
echo "▶ Target: $APP_DIR"

# ── deps ───────────────────────────────────────────────────────────────────
echo "▶ Installing jose + bcryptjs…"
npm install jose bcryptjs >/dev/null
npm install --save-dev @types/bcryptjs >/dev/null

# ── secret ───────────────────────────────────────────────────────────────────
SECRET="$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")"
touch .env.local
if grep -q '^AUTH_SECRET=' .env.local; then
  echo "[skip] AUTH_SECRET already in .env.local"
else
  printf '\nAUTH_SECRET=%s\n' "$SECRET" >> .env.local
  echo "▶ Wrote AUTH_SECRET to .env.local"
fi
if [ -f .env.local.example ] && ! grep -q '^AUTH_SECRET=' .env.local.example; then
  printf '\n# Auth — generate with: node -e "console.log(require(\\047crypto\\047).randomBytes(32).toString(\\047hex\\047))"\nAUTH_SECRET=\n' >> .env.local.example
fi

mkdir -p lib lib/actions app/login app/register app/account

# write <path> reads heredoc from stdin, skips if the file exists
write() {
  local path="$1"
  if [ -f "$path" ]; then
    echo "[skip] $path (already exists)"
    cat >/dev/null   # drain the heredoc
  else
    cat > "$path"
    echo "[write] $path"
  fi
}

# ── lib/auth.ts ──────────────────────────────────────────────────────────────
write lib/auth.ts <<'EOF'
import { SignJWT, jwtVerify } from "jose";
import { cookies } from "next/headers";

const COOKIE_NAME = "__session";

function getSecret(): Uint8Array {
  const s = process.env.AUTH_SECRET;
  if (!s) throw new Error("AUTH_SECRET env var is not set — add it to .env.local");
  return new TextEncoder().encode(s);
}

export type SessionPayload = { userId: string; email: string };

export async function createSession(payload: SessionPayload): Promise<void> {
  const token = await new SignJWT({ ...payload })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("30d")
    .sign(getSecret());

  const cookieStore = await cookies();
  cookieStore.set(COOKIE_NAME, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    maxAge: 60 * 60 * 24 * 30, // 30 days
    path: "/",
  });
}

export async function getSession(): Promise<SessionPayload | null> {
  try {
    const cookieStore = await cookies();
    const token = cookieStore.get(COOKIE_NAME)?.value;
    if (!token) return null;
    const { payload } = await jwtVerify(token, getSecret());
    return {
      userId: payload.userId as string,
      email: payload.email as string,
    };
  } catch {
    return null;
  }
}

export async function deleteSession(): Promise<void> {
  const cookieStore = await cookies();
  cookieStore.delete(COOKIE_NAME);
}

/** Reads the session and returns the userId, or throws if unauthenticated. */
export async function requireAuth(): Promise<string> {
  const session = await getSession();
  if (!session) throw new Error("Not authenticated");
  return session.userId;
}
EOF

# ── lib/actions/auth.ts ──────────────────────────────────────────────────────
# NOTE: assumes a `users` table (id, email, passwordHash, createdAt) in
# lib/db/schema.ts exported as schema.users, and a `db` client at lib/db/client.
write lib/actions/auth.ts <<'EOF'
"use server";

import bcrypt from "bcryptjs";
import { nanoid } from "nanoid";
import { eq } from "drizzle-orm";
import { redirect } from "next/navigation";
import { db, schema } from "@/lib/db/client";
import { createSession, deleteSession, getSession } from "@/lib/auth";

export type AuthState = { error: string } | null;

export async function registerAction(
  _prevState: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const email = ((formData.get("email") as string) ?? "").trim().toLowerCase();
  const password = (formData.get("password") as string) ?? "";

  if (!email || !password) return { error: "Email and password are required" };
  if (password.length < 8)
    return { error: "Password must be at least 8 characters" };

  const existing = await db
    .select({ id: schema.users.id })
    .from(schema.users)
    .where(eq(schema.users.email, email))
    .limit(1);
  if (existing.length > 0)
    return { error: "An account with that email already exists" };

  const passwordHash = await bcrypt.hash(password, 12);
  const id = nanoid();
  await db
    .insert(schema.users)
    .values({ id, email, passwordHash, createdAt: Date.now() });
  await createSession({ userId: id, email });
  redirect("/");
}

export async function loginAction(
  _prevState: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const email = ((formData.get("email") as string) ?? "").trim().toLowerCase();
  const password = (formData.get("password") as string) ?? "";

  if (!email || !password) return { error: "Email and password are required" };

  const rows = await db
    .select()
    .from(schema.users)
    .where(eq(schema.users.email, email))
    .limit(1);
  if (rows.length === 0) return { error: "Invalid email or password" };

  const user = rows[0];
  const valid = await bcrypt.compare(password, user.passwordHash);
  if (!valid) return { error: "Invalid email or password" };

  await createSession({ userId: user.id, email: user.email });
  redirect("/");
}

export async function logoutAction(): Promise<void> {
  await deleteSession();
  redirect("/login");
}

export type ChangePasswordState =
  | { ok: true; message: string }
  | { error: string }
  | null;

export async function changePasswordAction(
  _prevState: ChangePasswordState,
  formData: FormData,
): Promise<ChangePasswordState> {
  const session = await getSession();
  if (!session) return { error: "Not authenticated" };

  const current = (formData.get("current") as string) ?? "";
  const next = (formData.get("new") as string) ?? "";
  const confirm = (formData.get("confirm") as string) ?? "";

  if (!current || !next || !confirm) return { error: "All fields are required" };
  if (next.length < 8) return { error: "New password must be at least 8 characters" };
  if (next !== confirm) return { error: "New passwords do not match" };

  const rows = await db
    .select()
    .from(schema.users)
    .where(eq(schema.users.id, session.userId))
    .limit(1);
  if (rows.length === 0) return { error: "Account not found" };

  const valid = await bcrypt.compare(current, rows[0].passwordHash);
  if (!valid) return { error: "Current password is incorrect" };

  const passwordHash = await bcrypt.hash(next, 12);
  await db
    .update(schema.users)
    .set({ passwordHash })
    .where(eq(schema.users.id, session.userId));

  return { ok: true, message: "Password updated successfully" };
}
EOF

# ── proxy.ts (Next 16). For Next 15, rename to middleware.ts and the export to `middleware`.
write proxy.ts <<'EOF'
import { NextRequest, NextResponse } from "next/server";
import { jwtVerify } from "jose";

function getSecret(): Uint8Array {
  const s = process.env.AUTH_SECRET;
  if (!s) throw new Error("AUTH_SECRET env var is not set");
  return new TextEncoder().encode(s);
}

const PUBLIC_PATHS = ["/login", "/register"];

export async function proxy(req: NextRequest) {
  const { pathname } = req.nextUrl;

  if (PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"))) {
    return NextResponse.next();
  }

  const token = req.cookies.get("__session")?.value;
  if (!token) {
    return NextResponse.redirect(new URL("/login", req.url));
  }

  try {
    await jwtVerify(token, getSecret());
    return NextResponse.next();
  } catch {
    const res = NextResponse.redirect(new URL("/login", req.url));
    res.cookies.delete("__session");
    return res;
  }
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
EOF

# ── app/login/page.tsx ───────────────────────────────────────────────────────
write app/login/page.tsx <<'EOF'
"use client";

import { useActionState } from "react";
import Link from "next/link";
import { loginAction } from "@/lib/actions/auth";

export default function LoginPage() {
  const [state, action, isPending] = useActionState(loginAction, null);

  return (
    <main className="flex min-h-screen flex-col items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <h1 className="text-2xl font-bold tracking-tight">Sign in</h1>
        </div>

        <form action={action} className="space-y-4">
          <input
            name="email"
            type="email"
            required
            placeholder="Email"
            autoComplete="email"
            className="block w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-900"
          />
          <input
            name="password"
            type="password"
            required
            placeholder="Password"
            autoComplete="current-password"
            className="block w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-900"
          />
          {state?.error && (
            <p className="rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700">
              {state.error}
            </p>
          )}
          <button
            type="submit"
            disabled={isPending}
            className="w-full rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50 dark:bg-white dark:text-zinc-900"
          >
            {isPending ? "Signing in…" : "Sign in"}
          </button>
        </form>

        <p className="mt-4 text-center text-sm text-zinc-500">
          No account?{" "}
          <Link href="/register" className="font-medium underline">
            Create one
          </Link>
        </p>
      </div>
    </main>
  );
}
EOF

# ── app/register/page.tsx ────────────────────────────────────────────────────
write app/register/page.tsx <<'EOF'
"use client";

import { useActionState } from "react";
import Link from "next/link";
import { registerAction } from "@/lib/actions/auth";

export default function RegisterPage() {
  const [state, action, isPending] = useActionState(registerAction, null);

  return (
    <main className="flex min-h-screen flex-col items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <h1 className="text-2xl font-bold tracking-tight">Create account</h1>
        </div>

        <form action={action} className="space-y-4">
          <input
            name="email"
            type="email"
            required
            placeholder="Email"
            autoComplete="email"
            className="block w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-900"
          />
          <input
            name="password"
            type="password"
            required
            minLength={8}
            placeholder="Password (min 8 chars)"
            autoComplete="new-password"
            className="block w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-900"
          />
          {state?.error && (
            <p className="rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700">
              {state.error}
            </p>
          )}
          <button
            type="submit"
            disabled={isPending}
            className="w-full rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50 dark:bg-white dark:text-zinc-900"
          >
            {isPending ? "Creating…" : "Create account"}
          </button>
        </form>

        <p className="mt-4 text-center text-sm text-zinc-500">
          Already have an account?{" "}
          <Link href="/login" className="font-medium underline">
            Sign in
          </Link>
        </p>
      </div>
    </main>
  );
}
EOF

# ── app/account/page.tsx ─────────────────────────────────────────────────────
write app/account/page.tsx <<'EOF'
"use client";

import { useActionState } from "react";
import Link from "next/link";
import { changePasswordAction } from "@/lib/actions/auth";

export default function AccountPage() {
  const [state, action, isPending] = useActionState(changePasswordAction, null);

  return (
    <main className="mx-auto max-w-3xl px-4 py-8 sm:px-6 sm:py-10">
      <Link href="/" className="mb-4 inline-block text-xs text-zinc-400 hover:underline">
        ← Home
      </Link>
      <h1 className="mb-6 text-2xl font-bold tracking-tight">Account</h1>

      <section className="max-w-sm">
        <h2 className="mb-4 text-sm font-semibold uppercase tracking-wider text-zinc-500">
          Change password
        </h2>
        <form action={action} className="space-y-4">
          <input
            name="current"
            type="password"
            required
            placeholder="Current password"
            autoComplete="current-password"
            className="block w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-900"
          />
          <input
            name="new"
            type="password"
            required
            minLength={8}
            placeholder="New password (min 8 chars)"
            autoComplete="new-password"
            className="block w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-900"
          />
          <input
            name="confirm"
            type="password"
            required
            minLength={8}
            placeholder="Confirm new password"
            autoComplete="new-password"
            className="block w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm dark:border-zinc-700 dark:bg-zinc-900"
          />
          {state && "error" in state && (
            <p className="rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700">
              {state.error}
            </p>
          )}
          {state && "ok" in state && (
            <p className="rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-2 text-sm text-emerald-700">
              {state.message}
            </p>
          )}
          <button
            type="submit"
            disabled={isPending}
            className="w-full rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50 dark:bg-white dark:text-zinc-900"
          >
            {isPending ? "Updating…" : "Update password"}
          </button>
        </form>
      </section>
    </main>
  );
}
EOF

cat <<'CHECKLIST'

────────────────────────────────────────────────────────────────────────────
✓ Boilerplate written. Now the per-app steps (these depend on YOUR schema):

1. SCHEMA — in lib/db/schema.ts add a users table and a userId column to every
   per-user table. Give existing apps a safe default so old rows survive:

     export const users = sqliteTable("users", {
       id: text("id").primaryKey(),
       email: text("email").notNull().unique(),
       passwordHash: text("password_hash").notNull(),
       createdAt: integer("created_at").notNull(),
     });

     // on each per-user table:
     userId: text("user_id").notNull().default("__legacy__"),
     // and make any old single-column UNIQUE into a composite:
     //   uniqueIndex("..._user_x_idx").on(t.userId, t.someSlug)

   Leave SHARED/cache tables global (no userId) — e.g. a dictionary cache.

2. SCOPE QUERIES — top of every server action:  const userId = await requireAuth();
   then add  .where(eq(table.userId, userId))  to selects/updates/deletes, and
   userId to inserts. For getSavedWordIds-style helpers called pre-login, use
   getSession() and return empty when null.

3. MIGRATE — drizzle-kit push can't always alter UNIQUE/PK in place. If it errors,
   write a recreate-table migration (CREATE _new → INSERT SELECT with '__legacy__'
   → DROP → RENAME → recreate indexes) and apply via:  turso db shell <db> < migrate.sql

4. VERCEL — set the secret in prod and redeploy:
     vercel env add AUTH_SECRET production    # paste the value from your .env.local
     vercel redeploy <your-domain>            # env changes need a fresh deploy

5. CLAIM YOUR DATA — after you register your account, find your id and reassign:
     SELECT id, email FROM users;
     UPDATE <table> SET user_id='<your-id>' WHERE user_id='__legacy__';   -- each per-user table

6. Add an "Account" / "Sign out" affordance to your layout (see italian-tutor
   app/layout.tsx for the pattern using getSession() + logoutAction).

Verify:  npm run build   then   curl -I https://<domain>/   (expect 307 → /login)
────────────────────────────────────────────────────────────────────────────
CHECKLIST
