"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth, signOut } from "@/hooks/use-auth";

export default function Home() {
  const router = useRouter();
  const { user, isAuthenticated, isLoading } = useAuth();

  useEffect(() => {
    if (!isLoading && !isAuthenticated) {
      router.replace("/login");
    }
  }, [isAuthenticated, isLoading, router]);

  if (isLoading) {
    return (
      <div className="flex flex-col flex-1 items-center justify-center bg-zinc-50 font-sans dark:bg-black">
        <p className="text-zinc-500">Loading...</p>
      </div>
    );
  }

  if (!isAuthenticated) {
    return (
      <div className="flex flex-col flex-1 items-center justify-center bg-zinc-50 font-sans dark:bg-black">
        <p className="text-zinc-500">Redirecting to login...</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col flex-1 items-center justify-center bg-zinc-50 font-sans dark:bg-black">
      <main className="flex flex-1 w-full max-w-3xl flex-col items-center gap-8 py-32 px-16 bg-white dark:bg-black sm:items-start">
        <div className="flex items-center gap-4">
          {user?.image && (
            <img
              src={user.image}
              alt="Avatar"
              width={48}
              height={48}
              className="rounded-full"
            />
          )}
          <div>
            <p className="text-lg font-semibold text-zinc-900 dark:text-zinc-50">
              {user?.name}
            </p>
            <p className="text-sm text-zinc-500 dark:text-zinc-400">
              {user?.email}
            </p>
          </div>
        </div>

        <button
          type="button"
          onClick={() => signOut()}
          className="flex h-11 items-center justify-center rounded-lg border border-zinc-300 bg-white px-5 text-sm font-medium text-zinc-900 transition-colors hover:bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-100 dark:hover:bg-zinc-800"
        >
          Sign out
        </button>
      </main>
    </div>
  );
}
