import { auth, signOut } from "@/auth";
import Image from "next/image";

export default async function Home() {
  const session = await auth();

  return (
    <div className="flex flex-col flex-1 items-center justify-center bg-zinc-50 font-sans dark:bg-black">
      <main className="flex flex-1 w-full max-w-3xl flex-col items-center gap-8 py-32 px-16 bg-white dark:bg-black sm:items-start">
        <div className="flex items-center gap-4">
          {session?.user?.image && (
            <Image
              src={session.user.image}
              alt="Avatar"
              width={48}
              height={48}
              className="rounded-full"
            />
          )}
          <div>
            <p className="text-lg font-semibold text-zinc-900 dark:text-zinc-50">
              {session?.user?.name}
            </p>
            <p className="text-sm text-zinc-500 dark:text-zinc-400">
              {session?.user?.email}
            </p>
          </div>
        </div>

        <form
          action={async () => {
            "use server";
            await signOut({ redirectTo: "/login" });
          }}
        >
          <button
            type="submit"
            className="flex h-11 items-center justify-center rounded-lg border border-zinc-300 bg-white px-5 text-sm font-medium text-zinc-900 transition-colors hover:bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-100 dark:hover:bg-zinc-800"
          >
            Sign out
          </button>
        </form>
      </main>
    </div>
  );
}
