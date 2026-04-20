// TODO: Migrate to proxy.ts when next-auth adds support for Next.js 16 proxy convention
export { auth as middleware } from "@/auth";

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
